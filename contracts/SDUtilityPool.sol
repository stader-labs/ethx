// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/ISDIncentiveController.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPoolUtils.sol';
import './interfaces/IOperatorRewardsCollector.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SDUtilityPool is ISDUtilityPool, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint256 public constant DECIMAL = 1e18;

    uint256 public constant MAX_PROTOCOL_FEE = 1e17; // 10%

    // State variables

    /// @notice Fraction of fee currently set aside for protocol
    uint256 public protocolFeeFactor;

    /// @notice Block number that fee was last accrued at
    uint256 public accrualBlockNumber;

    /// @notice Accumulator of the total earned interest rate since start of pool
    uint256 public utilizeIndex;

    /// @notice Total amount of outstanding SD utilized
    uint256 public totalUtilizedSD;

    /// @notice Total amount of protocol fee
    uint256 public accumulatedProtocolFee;

    /// @notice utilization rate per block
    uint256 public utilizationRatePerBlock;

    /// @notice value of cToken supply
    uint256 public cTokenTotalSupply;

    /// @notice upper cap on ETH worth of SD utilized per validator
    uint256 public maxETHWorthOfSDPerValidator;

    /// @notice request ID to be finalized next
    uint256 public nextRequestIdToFinalize;

    /// @notice request ID to be assigned to a next withdraw request
    uint256 public nextRequestId;

    /// @notice amount of SD requested for withdraw
    uint256 public sdRequestedForWithdraw;

    /// @notice batch limit on withdraw requests to be finalized in single txn
    uint256 public finalizationBatchLimit;

    /// @notice amount of SD reserved for claim request
    uint256 public sdReservedForClaim;

    /// @notice minimum block delay between requesting for withdraw and claiming
    uint256 public undelegationPeriodInBlocks;

    /// @notice minimum block delay between requesting for withdraw and finalization of request
    uint256 public minBlockDelayToFinalizeRequest;

    /// @notice upper cap on user non redeemed withdraw request count
    uint256 public maxNonRedeemedDelegatorRequestCount;

    /// @notice address of staderConfig contract
    IStaderConfig public staderConfig;

    RiskConfig public riskConfig;

    OperatorLiquidation[] public liquidations;

    // Mappings
    mapping(address => UtilizerStruct) public override utilizerData;
    mapping(address => uint256) public override delegatorCTokenBalance;
    mapping(address => uint256) public override delegatorWithdrawRequestedCTokenCount;

    mapping(uint256 => DelegatorWithdrawInfo) public override delegatorWithdrawRequests;
    mapping(address => uint256[]) public override requestIdsByDelegatorAddress;
    mapping(address => uint256) private liquidationIndexByOperator;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //TODO sanjay set variables with right value
    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        staderConfig = IStaderConfig(_staderConfig);
        utilizeIndex = DECIMAL;
        utilizationRatePerBlock = 0;
        protocolFeeFactor = 0;
        nextRequestId = 1;
        nextRequestIdToFinalize = 1;
        finalizationBatchLimit = 50;
        undelegationPeriodInBlocks = 0;
        accrualBlockNumber = block.number;
        minBlockDelayToFinalizeRequest = 0;
        maxNonRedeemedDelegatorRequestCount = 0;
        maxETHWorthOfSDPerValidator = 1 ether;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice Sender delegate SD and cToken balance increases for sender
     * @dev Accrues fee whether or not the operation succeeds, unless reverted
     * @param sdAmount The amount of SD token to delegate
     */
    function delegate(uint256 sdAmount) external override whenNotPaused {
        accrueFee();
        ISDIncentiveController(staderConfig.getSDIncentiveController()).onDelegate(msg.sender);
        _delegate(sdAmount);
    }

    /**
     * @notice auxiliary method to put a withdrawal request, takes in cToken amount in input
     * @param _cTokenAmount amount of cToken
     * @return _requestId generated request ID for withdrawal
     */
    function requestWithdraw(uint256 _cTokenAmount) external override whenNotPaused returns (uint256 _requestId) {
        if (_cTokenAmount > delegatorCTokenBalance[msg.sender] - delegatorWithdrawRequestedCTokenCount[msg.sender]) {
            revert InvalidAmountOfWithdraw();
        }
        delegatorWithdrawRequestedCTokenCount[msg.sender] += _cTokenAmount;
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 sdRequested = (exchangeRate * _cTokenAmount) / DECIMAL;
        _requestId = _requestWithdraw(sdRequested, _cTokenAmount);
    }

    /**
     * @notice auxiliary method to put a withdrawal request, takes SD amount in input
     * @param _sdAmount amount of SD to withdraw
     * @return _requestId generated request ID for withdrawal
     */
    function requestWithdrawWithSDAmount(uint256 _sdAmount)
        external
        override
        whenNotPaused
        returns (uint256 _requestId)
    {
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 cTokenToReduce = (_sdAmount * DECIMAL) / exchangeRate;
        if (cTokenToReduce > delegatorCTokenBalance[msg.sender] - delegatorWithdrawRequestedCTokenCount[msg.sender]) {
            revert InvalidAmountOfWithdraw();
        }
        delegatorWithdrawRequestedCTokenCount[msg.sender] += cTokenToReduce;
        _requestId = _requestWithdraw(_sdAmount, cTokenToReduce);
    }

    /**
     * @notice finalize delegator's withdraw requests
     */
    function finalizeDelegatorWithdrawalRequest() external override whenNotPaused {
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 maxRequestIdToFinalize = Math.min(nextRequestId, nextRequestIdToFinalize + finalizationBatchLimit) - 1;
        uint256 requestId;
        uint256 sdToReserveToFinalizeRequests;
        for (requestId = nextRequestIdToFinalize; requestId <= maxRequestIdToFinalize; ) {
            DelegatorWithdrawInfo memory delegatorWithdrawInfo = delegatorWithdrawRequests[requestId];
            uint256 requiredSD = delegatorWithdrawInfo.sdExpected;
            uint256 amountOfcToken = delegatorWithdrawInfo.amountOfCToken;
            uint256 minSDRequiredToFinalizeRequest = Math.min(requiredSD, (amountOfcToken * exchangeRate) / DECIMAL);
            if (
                (sdToReserveToFinalizeRequests + minSDRequiredToFinalizeRequest > getPoolAvailableSDBalance()) ||
                (delegatorWithdrawInfo.requestBlock + minBlockDelayToFinalizeRequest > block.number)
            ) {
                break;
            }
            delegatorWithdrawRequests[requestId].sdFinalized = minSDRequiredToFinalizeRequest;
            sdRequestedForWithdraw -= requiredSD;
            sdToReserveToFinalizeRequests += minSDRequiredToFinalizeRequest;
            delegatorCTokenBalance[delegatorWithdrawInfo.owner] -= amountOfcToken;
            delegatorWithdrawRequestedCTokenCount[delegatorWithdrawInfo.owner] -= amountOfcToken;
            cTokenTotalSupply -= amountOfcToken;
            unchecked {
                ++requestId;
            }
        }
        // at here, upto (requestId-1) is finalized
        if (requestId > nextRequestIdToFinalize) {
            nextRequestIdToFinalize = requestId;
            sdReservedForClaim += sdToReserveToFinalizeRequests;
        }
        emit FinalizedWithdrawRequest(nextRequestIdToFinalize);
    }

    /**
     * @notice transfer the SD of finalized request to recipient and delete the request
     * @param _requestId request id to claim
     */
    function claim(uint256 _requestId) external override whenNotPaused {
        if (_requestId >= nextRequestIdToFinalize) {
            revert RequestIdNotFinalized(_requestId);
        }
        DelegatorWithdrawInfo memory delegatorRequest = delegatorWithdrawRequests[_requestId];
        if (msg.sender != delegatorRequest.owner) {
            revert CallerNotAuthorizedToRedeem();
        }
        if (block.number > delegatorRequest.requestBlock + undelegationPeriodInBlocks) {
            revert UndelegationPeriodNotPassed();
        }
        uint256 sdToTransfer = delegatorRequest.sdFinalized;
        sdReservedForClaim -= sdToTransfer;
        _deleteRequestId(_requestId);
        if (!IERC20(staderConfig.getStaderToken()).transfer(msg.sender, sdToTransfer)) {
            revert SDTransferFailed();
        }
        emit RequestRedeemed(msg.sender, sdToTransfer);
    }

    /**
     * @notice Sender utilizes SD from the pool to add it as collateral to run validators
     * @param utilizeAmount The amount of the SD token to utilize
     */
    function utilize(uint256 utilizeAmount) external override whenNotPaused {
        ISDCollateral sdCollateral = ISDCollateral(staderConfig.getSDCollateral());
        (, , uint256 nonTerminalKeyCount) = sdCollateral.getOperatorInfo(msg.sender);
        uint256 currentUtilizedSDCollateral = sdCollateral.operatorUtilizedSDBalance(msg.sender);
        uint256 maxSDUtilizeValue = nonTerminalKeyCount * sdCollateral.convertETHToSD(maxETHWorthOfSDPerValidator);
        if (currentUtilizedSDCollateral + utilizeAmount > maxSDUtilizeValue) {
            revert SDUtilizeLimitReached();
        }
        accrueFee();
        _utilize(msg.sender, utilizeAmount);
    }

    /**
     * @notice utilize SD from the pool to add it as collateral for `operator` to run validators
     * @dev only permissionless node registry contract can call
     * @param operator address of an ETHx operator
     * @param utilizeAmount The amount of the SD token to utilize
     * @param nonTerminalKeyCount count of operator's non terminal keys
     *
     */
    function utilizeWhileAddingKeys(
        address operator,
        uint256 utilizeAmount,
        uint256 nonTerminalKeyCount
    ) external override whenNotPaused {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.PERMISSIONLESS_NODE_REGISTRY());
        ISDCollateral sdCollateral = ISDCollateral(staderConfig.getSDCollateral());
        uint256 currentUtilizedSDCollateral = sdCollateral.operatorUtilizedSDBalance(operator);
        uint256 maxSDUtilizeValue = nonTerminalKeyCount * sdCollateral.convertETHToSD(maxETHWorthOfSDPerValidator);
        if (currentUtilizedSDCollateral + utilizeAmount > maxSDUtilizeValue) {
            revert SDUtilizeLimitReached();
        }
        accrueFee();
        _utilize(operator, utilizeAmount);
    }

    /**
     * @notice Sender repays their utilized SD, returns actual repayment amount
     * @param repayAmount The amount to repay
     */
    function repay(uint256 repayAmount) external whenNotPaused returns (uint256 repaidAmount) {
        accrueFee();
        repaidAmount = _repay(msg.sender, repayAmount);
        return repaidAmount;
    }

    /**
     * @notice Sender repays on behalf of utilizer, returns actual repayment amount
     * @param repayAmount The amount to repay
     */
    function repayOnBehalf(address utilizer, uint256 repayAmount)
        external
        override
        whenNotPaused
        returns (uint256 repaidAmount)
    {
        accrueFee();
        repaidAmount = _repay(utilizer, repayAmount);
        return repaidAmount;
    }

    /**
     * @notice call to withdraw protocol fee SD
     * @dev only `MANAGER` role can call
     * @param _amount amount of protocol fee in SD to withdraw
     */
    function withdrawProtocolFee(uint256 _amount) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        accrueFee();
        if (_amount > accumulatedProtocolFee) {
            revert InvalidWithdrawAmount();
        }
        accumulatedProtocolFee -= _amount;
        if (!IERC20(staderConfig.getStaderToken()).transfer(staderConfig.getStaderTreasury(), _amount)) {
            revert SDTransferFailed();
        }
        emit WithdrawnProtocolFee(_amount);
    }

    /// @notice for max approval to SD collateral contract for spending SD tokens
    function maxApproveSD() external override whenNotPaused {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        address sdCollateral = staderConfig.getSDCollateral();
        UtilLib.checkNonZeroAddress(sdCollateral);
        IERC20(staderConfig.getStaderToken()).approve(sdCollateral, type(uint256).max);
    }

    /**
     * @notice Applies accrued fee to total utilized and protocolFee
     * @dev This calculates fee accrued from the last check pointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueFee() public override whenNotPaused {
        /* Remember the initial block number */
        uint256 currentBlockNumber = block.number;

        /* Short-circuit accumulating 0 fee */
        if (accrualBlockNumber == currentBlockNumber) {
            return;
        }

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumber;

        /*
         * Calculate the fee accumulated into utilized and totalProtocolFee and the new index:
         *  simpleFeeFactor = utilizationRate * blockDelta
         *  feeAccumulated = simpleFeeFactor * totalUtilizedSD
         *  totalUtilizedSDNew = feeAccumulated + totalUtilizedSD
         *  totalProtocolFeeNew = feeAccumulated * protocolFeeFactor + totalProtocolFee
         *  utilizeIndexNew = simpleFeeFactor * utilizeIndex + utilizeIndex
         */

        uint256 simpleFeeFactor = utilizationRatePerBlock * blockDelta;
        uint256 feeAccumulated = (simpleFeeFactor * totalUtilizedSD) / DECIMAL;
        totalUtilizedSD += feeAccumulated;
        accumulatedProtocolFee += (protocolFeeFactor * feeAccumulated) / DECIMAL;
        utilizeIndex += (simpleFeeFactor * utilizeIndex) / DECIMAL;

        accrualBlockNumber = currentBlockNumber;

        emit AccruedFees(feeAccumulated, accumulatedProtocolFee, totalUtilizedSD);
    }

    function liquidationCall(address account) external override {
        UserData memory userData = getUserData(account);

        IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), userData.totalFeeSD);

        uint256 sdPriceInEth = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();

        utilizerData[account].utilizeIndex = 0;
        OperatorLiquidation memory liquidation = OperatorLiquidation(
            userData.totalFeeSD * sdPriceInEth,
            false,
            false,
            msg.sender
        );
        liquidations.push(liquidation);

        IPoolUtils poolUtils = IPoolUtils(staderConfig.getPoolUtils());
        poolUtils.processValidatorExitList(new bytes[](0));
    }

    function claimLiquidation(uint256 index) external override {
        OperatorLiquidation storage liquidation = liquidations[index];

        require(liquidation.isRepaid == true, 'Not claimable');
        require(liquidation.isClaimed == false, 'Already claimed');
        require(liquidation.liquidator == msg.sender, 'Not liquidator');

        liquidation.isClaimed = true;

        // TODO: transfer funds from operatorRewardsCollector to liquidator
    }

    /**
     * @notice Accrue fee to updated utilizeIndex and then calculate account's utilized balance using the updated utilizeIndex
     * @param account The address whose balance should be calculated after updating utilizeIndex
     * @return The calculated balance
     */
    function utilizerBalanceCurrent(address account) external override returns (uint256) {
        accrueFee();
        return _utilizerBalanceStoredInternal(account);
    }

    function repayLiquidation(address account) external override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.OPERATOR_REWARD_COLLECTOR());

        liquidations[liquidationIndexByOperator[account]].isRepaid = true;
    }

    /**
     * @notice Accrue fee then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external override returns (uint256) {
        accrueFee();
        return _exchangeRateStoredInternal();
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused
     */
    function pause() external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    //Setters

    /**
     * @notice updates protocol fee factor
     * @dev only `MANAGER` role can call
     * @param _protocolFeeFactor value of protocol fee factor
     */
    function updateProtocolFeeFactor(uint256 _protocolFeeFactor) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        if (_protocolFeeFactor > MAX_PROTOCOL_FEE) {
            revert InvalidInput();
        }
        protocolFeeFactor = _protocolFeeFactor;
        emit ProtocolFeeFactorUpdated(protocolFeeFactor);
    }

    /**
     * @notice updates the utilization rate
     * @dev only `MANAGER` role can call
     * @param _utilizationRatePerBlock new value of utilization rate per block
     */
    function updateUtilizationRatePerBlock(uint256 _utilizationRatePerBlock) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        utilizationRatePerBlock = _utilizationRatePerBlock;
        emit UtilizationRatePerBlockUpdated(utilizationRatePerBlock);
    }

    /**
     * @notice updates the maximum ETH worth of SD utilized per validator
     * @dev only `MANAGER` role can call
     * @param _maxETHWorthOfSDPerValidator new value of maximum ETH worth of SD utilized per validator
     */
    function updateMaxETHWorthOfSDPerValidator(uint256 _maxETHWorthOfSDPerValidator) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        maxETHWorthOfSDPerValidator = _maxETHWorthOfSDPerValidator;
        emit UpdatedMaxETHWorthOfSDPerValidator(_maxETHWorthOfSDPerValidator);
    }

    /**
     * @notice updates the batch limit to finalize withdraw request in a single txn
     * @dev only `MANAGER` role can call
     * @param _finalizationBatchLimit new value of batch limit
     */
    function updateFinalizationBatchLimit(uint256 _finalizationBatchLimit) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        if (_finalizationBatchLimit >= undelegationPeriodInBlocks) {
            revert InvalidInput();
        }
        finalizationBatchLimit = _finalizationBatchLimit;
        emit UpdatedFinalizationBatchLimit(finalizationBatchLimit);
    }

    /**
     * @notice updates the undelegation period of a withdraw request
     * @dev only `DEFAULT_ADMIN_ROLE` role can call
     * @param _undelegationPeriodInBlocks new value of undelegationPeriodInBlocks
     */
    function updateUndelegationPeriodInBlocks(uint256 _undelegationPeriodInBlocks)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_undelegationPeriodInBlocks <= finalizationBatchLimit) {
            revert InvalidInput();
        }
        undelegationPeriodInBlocks = _undelegationPeriodInBlocks;
        emit UpdatedUndelegationPeriodInBlocks(undelegationPeriodInBlocks);
    }

    /**
     * @notice updates the value of minimum block delay to finalize withdraw requests
     * @dev only `DEFAULT_ADMIN_ROLE` role can call
     * @param _minBlockDelayToFinalizeRequest new value of minBlockDelayToFinalizeRequest
     */
    function updateMinBlockDelayToFinalizeRequest(uint256 _minBlockDelayToFinalizeRequest)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        minBlockDelayToFinalizeRequest = _minBlockDelayToFinalizeRequest;
        emit UpdatedMinBlockDelayToFinalizeRequest(minBlockDelayToFinalizeRequest);
    }

    /**
     * @notice updates the value of `maxNonRedeemedDelegatorRequestCount`
     * @dev only `MANAGER` role can call
     * @param _count new count of maxNonRedeemedDelegatorRequest
     */
    function updateMaxNonRedeemedDelegatorRequestCount(uint256 _count) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        maxNonRedeemedDelegatorRequestCount = _count;
        emit UpdatedMaxNonRedeemedDelegatorRequestCount(_count);
    }

    /// @notice update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    //Getters

    /// @notice return the list of ongoing withdraw requestIds for a user
    function getRequestIdsByDelegator(address _delegator) external view override returns (uint256[] memory) {
        return requestIdsByDelegatorAddress[_delegator];
    }

    /**
     * @notice Return the utilized balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function utilizerBalanceStored(address account) external view override returns (uint256) {
        return _utilizerBalanceStoredInternal(account);
    }

    /// @notice Calculates the current delegation rate per block
    function getDelegationRate() external view override returns (uint256) {
        uint256 oneMinusProtocolFeeFactor = DECIMAL - protocolFeeFactor;
        uint256 rateToPool = (utilizationRatePerBlock * oneMinusProtocolFeeFactor) / DECIMAL;
        return (poolUtilization() * rateToPool) / DECIMAL;
    }

    /**
     * @notice Calculates the exchange rate from the SD to the SDx
     * @dev This function does not accrue fee before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view override returns (uint256) {
        return _exchangeRateStoredInternal();
    }

    /**
     * @notice view function to get utilizer latest utilized balance
     * @param _utilizer address of the utilizer
     */
    function getUtilizerLatestBalance(address _utilizer) external view override returns (uint256) {
        uint256 currentBlockNumber = block.number;
        uint256 blockDelta = currentBlockNumber - accrualBlockNumber;
        uint256 simpleFeeFactor = utilizationRatePerBlock * blockDelta;
        uint256 utilizeIndexNew = (simpleFeeFactor * utilizeIndex) / DECIMAL + utilizeIndex;
        UtilizerStruct storage utilizeSnapshot = utilizerData[_utilizer];

        if (utilizeSnapshot.principal == 0) {
            return 0;
        }
        uint256 principalTimesIndex = utilizeSnapshot.principal * utilizeIndexNew;
        return principalTimesIndex / utilizeSnapshot.utilizeIndex;
    }

    /**
     * @notice view function to get delegator latest SD balance
     * @param _delegator address of the delegator
     */
    function getDelegatorLatestSDBalance(address _delegator) external view override returns (uint256) {
        uint256 latestExchangeRate = getLatestExchangeRate();
        return (latestExchangeRate * delegatorCTokenBalance[_delegator]) / DECIMAL;
    }

    /**
     * @notice view function to get latest exchange rate
     */
    function getLatestExchangeRate() public view override returns (uint256) {
        uint256 currentBlockNumber = block.number;
        uint256 blockDelta = currentBlockNumber - accrualBlockNumber;
        uint256 simpleFeeFactor = utilizationRatePerBlock * blockDelta;
        uint256 feeAccumulated = (simpleFeeFactor * totalUtilizedSD) / DECIMAL;
        uint256 totalUtilizedSDNew = feeAccumulated + totalUtilizedSD;
        uint256 totalProtocolFeeNew = (protocolFeeFactor * feeAccumulated) / DECIMAL + accumulatedProtocolFee;
        if (cTokenTotalSupply == 0) {
            return DECIMAL;
        } else {
            uint256 poolBalancePlusUtilizedSDMinusReserves = getPoolAvailableSDBalance() +
                totalUtilizedSDNew -
                totalProtocolFeeNew;
            uint256 exchangeRate = (poolBalancePlusUtilizedSDMinusReserves * DECIMAL) / cTokenTotalSupply;
            return exchangeRate;
        }
    }

    function getPoolAvailableSDBalance() public view override returns (uint256) {
        return IERC20(staderConfig.getStaderToken()).balanceOf(address(this)) - sdReservedForClaim;
    }

    /// @notice Calculates the utilization of the utility pool
    function poolUtilization() public view override returns (uint256) {
        // Utilization is 0 when there are no utilized SD
        if (totalUtilizedSD == 0) {
            return 0;
        }

        return (totalUtilizedSD * DECIMAL) / (getPoolAvailableSDBalance() + totalUtilizedSD - accumulatedProtocolFee);
    }

    /**
     * @dev Assumes fee has already been accrued up to the current block
     * @param sdAmount The amount of the SD token to delegate
     */
    function _delegate(uint256 sdAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            revert AccrualBlockNumberNotLatest();
        }

        uint256 exchangeRate = _exchangeRateStoredInternal();

        if (!IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), sdAmount)) {
            revert SDTransferFailed();
        }
        uint256 cTokenShares = (sdAmount * DECIMAL) / exchangeRate;
        delegatorCTokenBalance[msg.sender] += cTokenShares;
        cTokenTotalSupply += cTokenShares;

        emit Delegated(msg.sender, sdAmount, cTokenShares);
    }

    function _requestWithdraw(uint256 _sdAmountToWithdraw, uint256 cTokenToBurn) internal returns (uint256) {
        if (requestIdsByDelegatorAddress[msg.sender].length + 1 > maxNonRedeemedDelegatorRequestCount) {
            revert MaxLimitOnWithdrawRequestCountReached();
        }
        sdRequestedForWithdraw += _sdAmountToWithdraw;
        delegatorWithdrawRequests[nextRequestId] = DelegatorWithdrawInfo(
            msg.sender,
            cTokenToBurn,
            _sdAmountToWithdraw,
            0,
            block.number
        );
        requestIdsByDelegatorAddress[msg.sender].push(nextRequestId);
        emit WithdrawRequestReceived(msg.sender, nextRequestId, _sdAmountToWithdraw);
        nextRequestId++;
        return nextRequestId - 1;
    }

    function _utilize(address utilizer, uint256 utilizeAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            revert AccrualBlockNumberNotLatest();
        }
        if (getPoolAvailableSDBalance() - sdRequestedForWithdraw < utilizeAmount) {
            revert InsufficientPoolBalance();
        }
        uint256 accountUtilizePrev = _utilizerBalanceStoredInternal(utilizer);

        utilizerData[utilizer].principal = accountUtilizePrev + utilizeAmount;
        utilizerData[utilizer].utilizeIndex = utilizeIndex;
        totalUtilizedSD = totalUtilizedSD + utilizeAmount;
        ISDCollateral(staderConfig.getSDCollateral()).depositUtilizedSD(utilizer, utilizeAmount);
        emit SDUtilized(utilizer, utilizeAmount);
    }

    function _repay(address utilizer, uint256 repayAmount) internal returns (uint256 repayAmountFinal) {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            revert AccrualBlockNumberNotLatest();
        }

        /* We fetch the amount the utilizer owes, with accumulated fee */
        uint256 accountUtilizePrev = _utilizerBalanceStoredInternal(utilizer);

        repayAmountFinal = (repayAmount == type(uint256).max || repayAmount > accountUtilizePrev)
            ? accountUtilizePrev
            : repayAmount;

        if (!IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), repayAmountFinal)) {
            revert SDTransferFailed();
        }
        if (!staderConfig.onlyStaderContract(msg.sender, staderConfig.SD_COLLATERAL())) {
            uint256 feeAccrued = accountUtilizePrev -
                ISDCollateral(staderConfig.getSDCollateral()).operatorUtilizedSDBalance(utilizer);
            if (repayAmountFinal > feeAccrued) {
                ISDCollateral(staderConfig.getSDCollateral()).reduceUtilizedSDPosition(
                    utilizer,
                    repayAmountFinal - feeAccrued
                );
            }
        }
        utilizerData[utilizer].principal = accountUtilizePrev - repayAmountFinal;
        utilizerData[utilizer].utilizeIndex = utilizeIndex;
        totalUtilizedSD = totalUtilizedSD - repayAmountFinal;
        emit Repaid(utilizer, repayAmountFinal);
    }

    /**
     * @notice Return the utilized balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return (calculated balance)
     */
    function _utilizerBalanceStoredInternal(address account) internal view returns (uint256) {
        /* Get utilizeBalance and utilizeIndex */
        UtilizerStruct storage utilizeSnapshot = utilizerData[account];

        /* If utilizeBalance = 0 then utilizeIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (utilizeSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new utilized balance using the utilize index:
         *  recentUtilizeBalance = utilizer.principal * utilizeIndex / utilizer.utilizeIndex
         */
        uint256 principalTimesIndex = utilizeSnapshot.principal * utilizeIndex;
        return principalTimesIndex / utilizeSnapshot.utilizeIndex;
    }

    /**
     * @notice Calculates the exchange rate from the SD to the SDx token
     * @dev This function does not accrue fee before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function _exchangeRateStoredInternal() internal view virtual returns (uint256) {
        if (cTokenTotalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return DECIMAL;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalUtilizedSD - totalFee) / totalSupply
             */
            uint256 poolBalancePlusUtilizedSDMinusReserves = getPoolAvailableSDBalance() +
                totalUtilizedSD -
                accumulatedProtocolFee;
            uint256 exchangeRate = (poolBalancePlusUtilizedSDMinusReserves * DECIMAL) / cTokenTotalSupply;

            return exchangeRate;
        }
    }

    /// delete entry from delegatorWithdrawRequests mapping and in requestIdsByDelegatorAddress mapping
    function _deleteRequestId(uint256 _requestId) internal {
        delete (delegatorWithdrawRequests[_requestId]);
        uint256 userRequestCount = requestIdsByDelegatorAddress[msg.sender].length;
        uint256[] storage requestIds = requestIdsByDelegatorAddress[msg.sender];
        for (uint256 i; i < userRequestCount; ) {
            if (_requestId == requestIds[i]) {
                requestIds[i] = requestIds[userRequestCount - 1];
                requestIds.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
        revert CannotFindRequestId();
    }

    function getUserData(address account) public view returns (UserData memory) {
        address staderOracle = staderConfig.getStaderOracle();
        uint256 sdPriceInEth = IStaderOracle(staderOracle).getSDPriceInETH();
        uint256 accountUtilizePrev = _utilizerBalanceStoredInternal(account);
        uint256 totalFeeSD = accountUtilizePrev - utilizerData[account].principal;

        // Multiplying other values by sdPriceInEth to avoid division
        uint256 totalCollateralInEth = getOperatorTotalEth(account);
        uint256 collateralTimesPrice = totalCollateralInEth * sdPriceInEth;

        // Ensuring that we do not divide by zero
        require(totalFeeSD > 0, 'Total Fee cannot be zero');
        uint256 healthFactor = (collateralTimesPrice * riskConfig.liquidationThreshold) / (totalFeeSD * sdPriceInEth);

        return UserData(totalFeeSD, totalCollateralInEth, 0, healthFactor, 0);
    }

    function getOperatorTotalEth(address operator) public view returns (uint256) {
        address nodeRegistry = staderConfig.getPermissionlessNodeRegistry();
        uint256 operatorId = INodeRegistry(nodeRegistry).operatorIDByAddress(operator);
        uint256 totalValidators = INodeRegistry(nodeRegistry).getOperatorTotalKeys(operatorId);

        uint256 totalEth = totalValidators * 2 ether;
        return totalEth;
    }

    function getOperatorLiquidation(address account) external view override returns (OperatorLiquidation memory) {
        return liquidations[liquidationIndexByOperator[account]];
    }
}
