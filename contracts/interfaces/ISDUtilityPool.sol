// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

/**
 * @dev Represents user's financial state in the system.
 */
struct UserData {
    uint256 totalInterestSD; // Total accrued SD interest for the user.
    uint256 totalCollateralInSD; // Total collateral in SD for the user.
    uint256 healthFactor; // Numerical health factor for liquidation risk.
    uint256 lockedEth; // Amount of ETH locked for liquidation.
}

/**
 * @dev Details of a liquidation event for an operator.
 */
struct OperatorLiquidation {
    uint256 totalAmountInEth; // Total ETH involved in liquidation.
    uint256 totalBonusInEth; // Bonus ETH in liquidation.
    uint256 totalFeeInEth; // Fee ETH collected from liquidation.
    bool isRepaid; // Indicates if liquidation is repaid.
    bool isClaimed; // Indicates if liquidation is claimed.
    address liquidator; // Address of the liquidator.
}

interface ISDUtilityPool {
    error InvalidInput();
    error NotClaimable();
    error AlreadyClaimed();
    error NotLiquidator();
    error NotLiquidatable();
    error SDTransferFailed();
    error UnHealthyPosition();
    error CannotFindRequestId();
    error SDUtilizeLimitReached();
    error InvalidWithdrawAmount();
    error InvalidAmountOfWithdraw();
    error InsufficientPoolBalance();
    error CallerNotAuthorizedToRedeem();
    error MaxLimitOnWithdrawRequestCountReached();
    error RequestIdNotFinalized(uint256 requestId);
    error AlreadyLiquidated();

    event WithdrawnProtocolFee(uint256 amount);
    event ProtocolFeeFactorUpdated(uint256 protocolFeeFactor);
    event UpdatedStaderConfig(address indexed _staderConfig);
    event SDUtilized(address utilizer, uint256 utilizeAmount);
    event FinalizedWithdrawRequest(uint256 nextRequestIdToFinalize);
    event RequestRedeemed(address caller, uint256 sdToTransfer);
    event Repaid(address indexed utilizer, uint256 repayAmount);
    event UpdatedMaxNonRedeemedDelegatorRequestCount(uint256 count);
    event UpdatedFinalizationBatchLimit(uint256 finalizationBatchLimit);
    event UtilizationRatePerBlockUpdated(uint256 utilizationRatePerBlock);
    event UpdatedMaxETHWorthOfSDPerValidator(uint256 maxETHWorthOfSDPerValidator);
    event Delegated(address indexed delegator, uint256 sdAmount, uint256 sdXToMint);
    event Redeemed(address indexed delegator, uint256 sdAmount, uint256 sdXAmount);
    event UpdatedMinBlockDelayToFinalizeRequest(uint256 minBlockDelayToFinalizeRequest);
    event LiquidationCall(
        address indexed account,
        uint256 totalLiquidationAmountInEth,
        uint256 liquidationBonusInEth,
        uint256 liquidationFeeInEth,
        address indexed liquidator
    );
    event CompleteLiquidation(uint256 indexed index);
    event RiskConfigUpdated(
        uint256 liquidationThreshold,
        uint256 liquidationBonusPercent,
        uint256 liquidationFeePercent,
        uint256 ltv
    );
    event AccruedFees(uint256 feeAccumulated, uint256 totalProtocolFee, uint256 totalUtilizedSD);
    event WithdrawRequestReceived(address caller, uint256 nextRequestId, uint256 sdAmountToWithdraw);
    event UpdatedConservativeEthPerKey(uint256 conservativeEthPerKey);

    struct UtilizerStruct {
        uint256 principal;
        uint256 utilizeIndex;
    }

    /// @notice structure representing a user request for withdrawal.
    struct DelegatorWithdrawInfo {
        address owner; // address that can claim on behalf of this request
        uint256 amountOfCToken; //amount of CToken to withdraw
        uint256 sdExpected; //sd requested at exchangeRate of withdraw
        uint256 sdFinalized; // final SD for claiming according to finalization exchange rate
        uint256 requestBlock; // block number of withdraw request
    }

    /**
     * @dev Defines risk parameters for liquidations and loans.
     */
    struct RiskConfig {
        uint256 liquidationThreshold; // Threshold for liquidation (%).
        uint256 liquidationBonusPercent; // Bonus for liquidators (%).
        uint256 liquidationFeePercent; // Liquidation fee (%).
        uint256 ltv; // Loan-to-Value ratio (%).
    }

    function delegate(uint256 sdAmount) external;

    function requestWithdraw(uint256 cTokenAmount) external returns (uint256);

    function requestWithdrawWithSDAmount(uint256 sdAmount) external returns (uint256);

    function finalizeDelegatorWithdrawalRequest() external;

    function claim(uint256 requestId) external;

    function utilize(uint256 utilizeAmount) external;

    function utilizeWhileAddingKeys(
        address operator,
        uint256 utilizeAmount,
        uint256 nonTerminalKeyCount
    ) external;

    function repay(uint256 repayAmount) external returns (uint256, uint256);

    function repayOnBehalf(address utilizer, uint256 repayAmount) external returns (uint256, uint256);

    function completeLiquidation(address account) external;

    function withdrawProtocolFee(uint256 _amount) external;

    function accrueFee() external;

    function liquidationCall(address account) external;

    function utilizerBalanceCurrent(address account) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function maxApproveSD() external;

    //Setters

    function updateProtocolFee(uint256 _protocolFee) external;

    function updateUtilizationRatePerBlock(uint256 _utilizationRatePerBlock) external;

    function updateMaxETHWorthOfSDPerValidator(uint256 _maxETHWorthOfSDPerValidator) external;

    function updateFinalizationBatchLimit(uint256 _finalizationBatchLimit) external;

    function updateMinBlockDelayToFinalizeRequest(uint256 _minBlockDelayToFinalizeRequest) external;

    function updateMaxNonRedeemedDelegatorRequestCount(uint256 _count) external;

    function updateStaderConfig(address _staderConfig) external;

    function updateConservativeEthPerKey(uint256 _newEthPerKey) external;

    //Getters
    function maxETHWorthOfSDPerValidator() external view returns (uint256);

    function cTokenTotalSupply() external view returns (uint256);

    function delegatorCTokenBalance(address) external view returns (uint256);

    function delegatorWithdrawRequestedCTokenCount(address) external view returns (uint256);

    function getPoolAvailableSDBalance() external view returns (uint256);

    function sdRequestedForWithdraw() external view returns (uint256);

    function accumulatedProtocolFee() external view returns (uint256);

    function utilizerBalanceStored(address account) external view returns (uint256);

    function getDelegationRatePerBlock() external view returns (uint256);

    function utilizationRatePerBlock() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function poolUtilization() external view returns (uint256);

    function getUtilizerLatestBalance(address _utilizer) external view returns (uint256);

    function getDelegatorLatestSDBalance(address _delegator) external view returns (uint256);

    function getLatestExchangeRate() external view returns (uint256);

    function utilizerData(address) external view returns (uint256 principal, uint256 utilizeIndex);

    function getOperatorLiquidation(address) external view returns (OperatorLiquidation memory);

    function delegatorWithdrawRequests(uint256)
        external
        view
        returns (
            address owner,
            uint256 amountOfCToken,
            uint256 sdExpected,
            uint256 sdFinalized,
            uint256 requestBlock
        );

    function requestIdsByDelegatorAddress(address, uint256) external view returns (uint256);

    function getRequestIdsByDelegator(address _owner) external view returns (uint256[] memory);

    function getLiquidationThreshold() external view returns (uint256);

    function getUserData(address account) external view returns (UserData memory);
}
