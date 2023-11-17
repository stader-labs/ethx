// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/ISDIncentiveController.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SDUtilityPool is ISDUtilityPool, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    //TODO include WhenNotPaused modifier in the contract
    uint256 public constant DECIMAL = 1e18;

    // State variables

    /**
     * @notice Fraction of fee currently set aside for protocol
     */
    uint256 public protocolFeeFactor;

    /**
     * @notice Block number that fee was last accrued at
     */
    uint256 public accrualBlockNumber;

    /**
     * @notice Accumulator of the total earned fee rate since start of pool
     */
    uint256 public utilizeIndex;

    /**
     * @notice Total amount of outstanding SD utilized
     */
    uint256 public totalUtilizedSD;

    /**
     * @notice Total amount of protocol fee
     */
    uint256 public totalProtocolFee;

    // Additional state variables
    uint256 public utilizationRatePerBlock;
    uint256 public cTokenTotalSupply;
    uint256 public maxETHWorthOfSDPerValidator;
    uint256 public nextRequestIdToFinalize;
    uint256 public nextRequestId;
    uint256 public sdRequestedForWithdraw;
    uint256 public finalizationBatchLimit;
    uint256 public sdReservedForClaim;
    uint256 public undelegationPeriodInBlocks;
    uint256 public minBlockDelayToFinalizeRequest;

    //upper cap on user non redeemed withdraw request count
    uint256 public maxNonRedeemedDelegatorRequestCount;

    bytes32 public constant NODE_REGISTRY_CONTRACT = keccak256('NODE_REGISTRY_CONTRACT');
    IStaderConfig public staderConfig;
    RiskConfig public riskConfig;

    // Mappings
    mapping(address => UtilizerStruct) public override utilizerData;
    mapping(address => uint256) public override delegatorCTokenBalance;
    mapping(uint256 => DelegatorWithdrawInfo) public override delegatorWithdrawRequests;
    mapping(address => uint256[]) public override requestIdsByDelegatorAddress;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //TODO sanjay define initial params like utilize rate, utilizeIndex
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
        accrualBlockNumber = block.number;
        maxETHWorthOfSDPerValidator = 1 ether;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice Sender delegate SD and cToken balance increases for sender
     * @dev Accrues fee whether or not the operation succeeds, unless reverted
     * @param sdAmount The amount of SD token to delegate
     */
    function delegate(uint256 sdAmount) external override {
        accrueFee();
        ISDIncentiveController(staderConfig.getSDIncentiveController()).onDelegate(msg.sender);
        _delegate(sdAmount);
    }

    /**
     * @notice auxiliary method to put a withdrawal request, takes in cToken in input
     * @param _cTokenAmount amount of cToken
     * @return _requestId generated request ID for withdrawal
     */
    function requestWithdraw(uint256 _cTokenAmount) external override returns (uint256 _requestId) {
        if (_cTokenAmount > delegatorCTokenBalance[msg.sender]) {
            revert InvalidAmountOfWithdraw();
        }
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
    function requestWithdrawWithSDAmount(uint256 _sdAmount) external override returns (uint256 _requestId) {
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 cTokenToBurn = (_sdAmount * DECIMAL) / exchangeRate;
        if (cTokenToBurn > delegatorCTokenBalance[msg.sender]) {
            revert InvalidAmountOfWithdraw();
        }
        _requestId = _requestWithdraw(_sdAmount, cTokenToBurn);
    }

    /**
     * @notice finalize delegator's withdraw requests
     */
    function finalizeDelegatorWithdrawalRequest() external override {
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 maxRequestIdToFinalize = Math.min(nextRequestId, nextRequestIdToFinalize + finalizationBatchLimit) - 1;
        uint256 requestId;
        uint256 sdToReserveToFinalizeRequest;
        for (requestId = nextRequestIdToFinalize; requestId <= maxRequestIdToFinalize; ) {
            DelegatorWithdrawInfo memory delegatorWithdrawInfo = delegatorWithdrawRequests[requestId];
            uint256 requiredSD = delegatorWithdrawInfo.sdExpected;
            uint256 amountOfcToken = delegatorWithdrawInfo.amountOfCToken;
            uint256 minSDRequiredToFinalizeRequest = Math.min(requiredSD, (amountOfcToken * exchangeRate) / DECIMAL);
            if (
                (sdToReserveToFinalizeRequest + minSDRequiredToFinalizeRequest > getPoolAvailableSDBalance()) ||
                (delegatorWithdrawInfo.requestBlock + minBlockDelayToFinalizeRequest > block.number)
            ) {
                break;
            }
            delegatorWithdrawRequests[requestId].sdFinalized = minSDRequiredToFinalizeRequest;
            sdRequestedForWithdraw -= requiredSD;
            sdToReserveToFinalizeRequest += minSDRequiredToFinalizeRequest;
            delegatorCTokenBalance[delegatorWithdrawInfo.owner] -= amountOfcToken;
            cTokenTotalSupply -= amountOfcToken;
            unchecked {
                ++requestId;
            }
        }
        // at here, upto (requestId-1) is finalized
        if (requestId > nextRequestIdToFinalize) {
            nextRequestIdToFinalize = requestId;
            sdReservedForClaim += sdToReserveToFinalizeRequest;
        }
    }

    /**
     * @notice transfer the SD of finalized request to recipient and delete the request
     * @param _requestId request id to claim
     */
    function claim(uint256 _requestId) external override {
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
        _deleteRequestId(_requestId);
        if (!IERC20(staderConfig.getStaderToken()).transfer(msg.sender, sdToTransfer)) {
            revert SDTransferFailed();
        }
        emit RequestRedeemed(msg.sender, sdToTransfer);
    }

    /// @notice return the list of ongoing withdraw requestIds for a user
    function getRequestIdsByDelegator(address _delegator) external view override returns (uint256[] memory) {
        return requestIdsByDelegatorAddress[_delegator];
    }

    /**
     * @notice Sender utilize SD from the pool to add it as collateral to run validators
     * @param utilizeAmount The amount of the SD token to utilize
     */
    function utilize(uint256 utilizeAmount) external override {
        ISDCollateral sdCollateral = ISDCollateral(staderConfig.getSDCollateral());
        (, , uint256 nonTerminalKeyCount) = sdCollateral.getOperatorInfo(msg.sender);
        uint256 currentUtilizeSDCollateral = sdCollateral.operatorUtilizedSDBalance(msg.sender);
        uint256 maxSDUtilizeValue = nonTerminalKeyCount * sdCollateral.convertETHToSD(maxETHWorthOfSDPerValidator);
        if (currentUtilizeSDCollateral + utilizeAmount > maxSDUtilizeValue) {
            revert SDUtilizeLimitReached();
        }
        accrueFee();
        _utilize(msg.sender, utilizeAmount);
    }

    /**
     * @notice utilize SD from the pool to add it as collateral for `operator` to run validators
     * @dev only `NODE REGISTRY` contract can call
     * @param operator address of an ETHx operator
     * @param utilizeAmount The amount of the SD token to utilize
     * @param nonTerminalKeyCount count of operator's non terminal keys
     *
     */
    //TODO can we remove this ROLE and use something else?
    function utilizeWhileAddingKeys(
        address operator,
        uint256 utilizeAmount,
        uint256 nonTerminalKeyCount
    ) external override onlyRole(NODE_REGISTRY_CONTRACT) {
        ISDCollateral sdCollateral = ISDCollateral(staderConfig.getSDCollateral());
        uint256 currentUtilizeSDCollateral = sdCollateral.operatorUtilizedSDBalance(operator);
        uint256 maxSDUtilizeValue = nonTerminalKeyCount * sdCollateral.convertETHToSD(maxETHWorthOfSDPerValidator);
        if (currentUtilizeSDCollateral + utilizeAmount > maxSDUtilizeValue) {
            revert SDUtilizeLimitReached();
        }
        accrueFee();
        _utilize(operator, utilizeAmount);
    }

    /**
     * @notice Sender repays their own utilize
     * @param repayAmount The amount to repay
     */
    function repay(uint256 repayAmount) external override {
        accrueFee();
        _repay(msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays on behalf of utilizer
     * @param repayAmount The amount to repay
     */
    function repayOnBehalf(address utilizer, uint256 repayAmount) external override {
        accrueFee();
        _repay(utilizer, repayAmount);
    }

    function handleUtilizerSDSlashing(address _utilizer, uint256 _slashSDAmount) external override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_COLLATERAL());
        accrueFee();
        //TODO should we leave utilize position worth of fee?
        uint256 accountUtilizePrev = _utilizerBalanceStoredInternal(_utilizer);
        utilizerData[_utilizer].principal = accountUtilizePrev - _slashSDAmount;
        utilizerData[_utilizer].utilizeIndex = utilizeIndex;
        totalUtilizedSD = totalUtilizedSD - _slashSDAmount;
        //TODO emit an event
    }

    /// @notice for max approval to SD collateral contract for spending SD tokens
    function maxApproveSD() external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        address sdCollateral = staderConfig.getSDCollateral();
        UtilLib.checkNonZeroAddress(sdCollateral);
        IERC20(staderConfig.getStaderToken()).approve(sdCollateral, type(uint256).max);
    }

    /**
     * @notice Applies accrued fee to total utilize and protocolFee
     * @dev This calculates fee accrued from the last check pointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueFee() public override {
        /* Remember the initial block number */
        uint256 currentBlockNumber = block.number;

        /* Short-circuit accumulating 0 fee */
        if (accrualBlockNumber == currentBlockNumber) {
            return;
        }

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumber;

        /*
         * Calculate the fee accumulated into utilize and totalProtocolFee and the new index:
         *  simpleFeeFactor = utilizationRate * blockDelta
         *  feeAccumulated = simpleFeeFactor * utilizePrior
         *  totalUtilizeNew = feeAccumulated + utilizePrior
         *  totalProtocolFeeNew = feeAccumulated * protocolFeeFactor + totalProtocolFee
         *  utilizeIndexNew = simpleFeeFactor * utilizeIndex + utilizeIndex
         */

        uint256 simpleFeeFactor = utilizationRatePerBlock * blockDelta;
        uint256 feeAccumulated = (simpleFeeFactor * totalUtilizedSD) / DECIMAL;
        totalUtilizedSD = feeAccumulated + totalUtilizedSD;
        totalProtocolFee = (protocolFeeFactor * feeAccumulated) / DECIMAL + totalProtocolFee;
        utilizeIndex = (simpleFeeFactor * utilizeIndex) / DECIMAL + utilizeIndex;

        accrualBlockNumber = currentBlockNumber;

        emit AccruedFees(feeAccumulated, totalProtocolFee, totalUtilizedSD);
    }

    function liquidationCall(address account) external override {
        UserData memory userData = getUserData(account);

        IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), userData.totalFeeSD);

        uint256 sdPriceInEth = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();

        utilizerData[account].utilizeIndex = 0;
    }

    /**
     * @notice Accrue fee to updated utilizeIndex and then calculate account's utilize balance using the updated utilizeIndex
     * @param account The address whose balance should be calculated after updating utilizeIndex
     * @return The calculated balance
     */
    function utilizerBalanceCurrent(address account) external override returns (uint256) {
        accrueFee();
        return _utilizerBalanceStoredInternal(account);
    }

    /**
     * @notice Return the utilize balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function utilizerBalanceStored(address account) external view override returns (uint256) {
        return _utilizerBalanceStoredInternal(account);
    }

    /// @notice Calculates the utilization of the utility pool
    function poolUtilization() public view override returns (uint256) {
        // Utilization is 0 when there are no utilize
        if (totalUtilizedSD == 0) {
            return 0;
        }

        return (totalUtilizedSD * DECIMAL) / (getPoolAvailableSDBalance() + totalUtilizedSD - totalProtocolFee);
    }

    /// @notice Calculates the current delegation rate per block
    function getDelegationRate() external view override returns (uint256) {
        uint256 oneMinusProtocolFeeFactor = DECIMAL - protocolFeeFactor;
        uint256 rateToPool = (utilizationRatePerBlock * oneMinusProtocolFeeFactor) / DECIMAL;
        return (poolUtilization() * rateToPool) / DECIMAL;
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
     * @notice Calculates the exchange rate from the SD to the SDx
     * @dev This function does not accrue fee before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view override returns (uint256) {
        return _exchangeRateStoredInternal();
    }

    /**
     * @notice view function to get utilizer latest utilize balance
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
        uint256 totalProtocolFeeNew = (protocolFeeFactor * feeAccumulated) / DECIMAL + totalProtocolFee;
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
        uint256 cTokenToMint = (sdAmount * DECIMAL) / exchangeRate;
        delegatorCTokenBalance[msg.sender] += cTokenToMint;
        cTokenTotalSupply += cTokenToMint;

        emit Delegated(msg.sender, sdAmount, cTokenToMint);
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
        //TODO @sanjay emit events
    }

    function _repay(address utilizer, uint256 repayAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            revert AccrualBlockNumberNotLatest();
        }

        /* We fetch the amount the utilizer owes, with accumulated fee */
        uint256 accountUtilizePrev = _utilizerBalanceStoredInternal(utilizer);

        uint256 repayAmountFinal = (repayAmount == type(uint256).max || repayAmount > accountUtilizePrev)
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
     * @notice Return the utilize balance of account based on stored data
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

        /* Calculate new utilize balance using the utilize index:
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
                totalProtocolFee;
            uint256 exchangeRate = (poolBalancePlusUtilizedSDMinusReserves * DECIMAL) / cTokenTotalSupply;

            return exchangeRate;
        }
    }

    // delete entry from delegatorWithdrawRequests mapping and in requestIdsByDelegatorAddress mapping
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
}
