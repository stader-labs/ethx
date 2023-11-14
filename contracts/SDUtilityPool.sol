// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDIncentiveController.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SDUtilityPool is ISDUtilityPool, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint256 constant DECIMAL = 1e18;

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

    //TODO sanjay Getter, Setter for below params
    /**
     * @notice Total amount of protocol fee
     */
    uint256 public totalProtocolFee;

    uint256 public utilizationRatePerBlock;

    uint256 public cTokenTotalSupply;

    uint256 public maxETHWorthOfSDPerValidator;

    uint256 public nextRequestIdToFinalize;
    uint256 public nextRequestId;
    uint256 public sdRequestedForWithdraw;
    uint256 public finalizationBatchLimit;
    uint256 public sdReservedForClaim;

    //upper cap on user non redeemed withdraw request count
    uint256 public maxNonRedeemedDelegatorRequestCount;

    bytes32 public constant NODE_REGISTRY_CONTRACT = keccak256('NODE_REGISTRY_CONTRACT');

    IStaderConfig public staderConfig;

    struct UtilizerStruct {
        uint256 principal;
        uint256 utilizeIndex;
    }

    /// @notice structure representing a user request for withdrawal.
    struct DelegatorWithdrawInfo {
        address owner; // address that can claim on behalf of this request
        uint256 amountOfCToken; //amount of CToken to withdraw
        uint256 amountOfSD; //amount of SD to withdraw
        uint256 requestBlock; // block number of withdraw request
    }

    mapping(address => UtilizerStruct) public utilizerData;

    mapping(address => uint256) public delegatorCTokenBalance;

    mapping(uint256 => DelegatorWithdrawInfo) public delegatorWithdrawRequests;

    mapping(address => uint256[]) public requestIdsByDelegatorAddress;

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
     * @notice Sender delegate SD and receive SDx in return
     * @dev Accrues fee whether or not the operation succeeds, unless reverted
     * @param sdAmount The amount of SD token to delegate
     */
    function delegate(uint256 sdAmount) external {
        accrueFee();
        ISDIncentiveController(staderConfig.getSDIncentiveController()).onDelegate(msg.sender);
        _delegate(sdAmount);
    }

    /**
     * @notice auxiliary method to put a withdrawal request
     * @param _cTokenAmount amount of cToken to withdraw
     * @return _requestId generated request ID for withdrawal
     */
    function requestWithdraw(uint256 _cTokenAmount) external returns (uint256 _requestId) {
        if (_cTokenAmount > delegatorCTokenBalance[msg.sender]) {
            revert InvalidAmountOfWithdraw();
        }
        accrueFee();
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 sdRequested = (exchangeRate * _cTokenAmount) / DECIMAL;
        _requestId = _requestWithdraw(sdRequested, _cTokenAmount);
    }

    /**
     * @notice auxiliary method to put a withdrawal request
     * @param _sdAmount amount of SD to withdraw
     * @return _requestId generated request ID for withdrawal
     */
    function requestWithdrawWithSDAmount(uint256 _sdAmount) external returns (uint256 _requestId) {
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
    function finalizeDelegatorWithdrawalRequest() external {
        uint256 maxRequestIdToFinalize = Math.min(nextRequestId, nextRequestIdToFinalize + finalizationBatchLimit) - 1;
        uint256 requestId;
        uint256 sdToReserveToFinalizeRequest;
        uint256 availableSDInPool = getPoolAvailableSDBalance();
        for (requestId = nextRequestIdToFinalize; requestId <= maxRequestIdToFinalize; ) {
            DelegatorWithdrawInfo memory delegatorWithdrawInfo = delegatorWithdrawRequests[requestId];
            uint256 requiredSD = delegatorWithdrawInfo.amountOfSD;
            if (
                (sdToReserveToFinalizeRequest + requiredSD > availableSDInPool) ||
                (delegatorWithdrawInfo.requestBlock + staderConfig.getMinBlockDelayToFinalizeWithdrawRequest() >
                    block.number)
            ) {
                break;
            }
            sdRequestedForWithdraw -= requiredSD;
            sdToReserveToFinalizeRequest += requiredSD;
            delegatorCTokenBalance[delegatorWithdrawInfo.owner] -= delegatorWithdrawInfo.amountOfCToken;
            cTokenTotalSupply -= delegatorWithdrawInfo.amountOfCToken;
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
     * @notice transfer the eth of finalized request to recipient and delete the request
     * @param _requestId request id to redeem
     */
    function claim(uint256 _requestId) external {
        if (_requestId >= nextRequestIdToFinalize) {
            revert requestIdNotFinalized(_requestId);
        }
        DelegatorWithdrawInfo memory delegatorRequest = delegatorWithdrawRequests[_requestId];
        if (msg.sender != delegatorRequest.owner) {
            revert CallerNotAuthorizedToRedeem();
        }
        uint256 sdToTransfer = delegatorRequest.amountOfSD;
        _deleteRequestId(_requestId);
        if (!IERC20(staderConfig.getStaderToken()).transferFrom(address(this), msg.sender, sdToTransfer)) {
            revert SDTransferFailed();
        }
        emit RequestRedeemed(msg.sender, sdToTransfer);
    }

    /// @notice return the list of ongoing withdraw requestIds for a user
    function getRequestIdsByDelegator(address _delegator) external view returns (uint256[] memory) {
        return requestIdsByDelegatorAddress[_delegator];
    }

    /**
     * @notice Sender utilize SD from the protocol to add it as collateral to run validators
     * @param utilizeAmount The amount of the SD token to utilize
     */
    function utilize(uint256 utilizeAmount) external {
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
     * @notice utilize SD from the protocol to add it as collateral for `operator` to run validators
     * @dev only `NODE REGISTRY` contract call call
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
    ) external onlyRole(NODE_REGISTRY_CONTRACT) {
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
    function repay(uint256 repayAmount) external {
        accrueFee();
        _repay(msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays on behalf of utilizer
     * @param repayAmount The amount to repay
     */
    function repayOnBehalf(address utilizer, uint256 repayAmount) external {
        accrueFee();
        _repay(utilizer, repayAmount);
    }

    /**
     * @notice Applies accrued fee to total utilize and protocolFee
     * @dev This calculates fee accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueFee() public {
        /* Remember the initial block number */
        uint256 currentBlockNumber = block.number;
        uint256 accrualBlockNumberPrior = accrualBlockNumber;

        /* Short-circuit accumulating 0 fee */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return;
        }

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

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

    /**
     * @notice Accrue fee to updated utilizeIndex and then calculate account's utilize balance using the updated utilizeIndex
     * @param account The address whose balance should be calculated after updating utilizeIndex
     * @return The calculated balance
     */
    function utilizerBalanceCurrent(address account) external returns (uint256) {
        accrueFee();
        return _utilizerBalanceStoredInternal(account);
    }

    /**
     * @notice Return the utilize balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function utilizerBalanceStored(address account) external view returns (uint256) {
        return _utilizerBalanceStoredInternal(account);
    }

    /// @notice Calculates the utilization of the utility pool
    function poolUtilization() public view returns (uint256) {
        // Utilization is 0 when there are no utilize
        if (totalUtilizedSD == 0) {
            return 0;
        }

        return (totalUtilizedSD * DECIMAL) / (getPoolAvailableSDBalance() + totalUtilizedSD - totalProtocolFee);
    }

    /// @notice Calculates the current delegation rate per block
    function getDelegationRate() external view returns (uint256) {
        uint256 oneMinusProtocolFeeFactor = DECIMAL - protocolFeeFactor;
        uint256 rateToPool = (utilizationRatePerBlock * oneMinusProtocolFeeFactor) / DECIMAL;
        return (poolUtilization() * rateToPool) / DECIMAL;
    }

    /**
     * @notice Accrue fee then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint256) {
        accrueFee();
        return _exchangeRateStoredInternal();
    }

    /**
     * @notice Calculates the exchange rate from the SD to the SDx
     * @dev This function does not accrue fee before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256) {
        return _exchangeRateStoredInternal();
    }

    /**
     * @dev Assumes fee has already been accrued up to the current block
     * @param sdAmount The amount of the SD token to supply
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
        if (getPoolAvailableSDBalance() < utilizeAmount) {
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

        if (!staderConfig.onlyStaderContract(msg.sender, staderConfig.SD_COLLATERAL())) {
            if (!IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), repayAmountFinal)) {
                revert SDTransferFailed();
            }
            uint256 feeAccrued = accountUtilizePrev -
                ISDCollateral(staderConfig.getSDCollateral()).operatorUtilizedSDBalance(utilizer);
            if (repayAmountFinal > feeAccrued) {
                ISDCollateral(staderConfig.getSDCollateral()).reduceUtilizedSDPosition(
                    utilizer,
                    repayAmountFinal - feeAccrued
                );
            }
        }

        /* We write the previously calculated values into storage */
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
        //fetch totalSupply here
        uint256 _totalSupply;
        // uint256 _totalSupply = SDX(staderConfig.getSDxToken()).totalSupply();
        if (_totalSupply == 0) {
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
            uint256 exchangeRate = (poolBalancePlusUtilizedSDMinusReserves * DECIMAL) / _totalSupply;

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

    function getPoolAvailableSDBalance() public view returns (uint256) {
        return IERC20(staderConfig.getStaderToken()).balanceOf(address(this)) - sdReservedForClaim;
    }
}
