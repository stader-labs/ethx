// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ISDUtilityPool {
    error SDTransferFailed();
    error CannotFindRequestId();
    error SDUtilizeLimitReached();
    error InvalidAmountOfWithdraw();
    error InsufficientPoolBalance();
    error AccrualBlockNumberNotLatest();
    error CallerNotAuthorizedToRedeem();
    error UndelegationPeriodNotPassed();
    error MaxLimitOnWithdrawRequestCountReached();
    error RequestIdNotFinalized(uint256 requestId);

    event UpdatedStaderConfig(address indexed _staderConfig);
    event RequestRedeemed(address caller, uint256 sdToTransfer);
    event Delegated(address indexed delegator, uint256 sdAmount, uint256 sdXToMint);
    event Redeemed(address indexed delegator, uint256 sdAmount, uint256 sdXAmount);
    event Repaid(address indexed utilizer, uint256 repayAmount);

    event AccruedFees(uint256 feeAccumulated, uint256 totalProtocolFee, uint256 totalUtilizedSD);

    event WithdrawRequestReceived(address caller, uint256 nextRequestId, uint256 sdAmountToWithdraw);

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

    function repay(uint256 repayAmount) external;

    function repayOnBehalf(address utilizer, uint256 repayAmount) external;

    function accrueFee() external;

    function utilizerBalanceCurrent(address account) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function maxApproveSD() external;

    function handleUtilizerSDSlashing(address _utilizer, uint256 _slashSDAmount) external;

    //Getters

    function cTokenTotalSupply() external view returns (uint256);

    function delegatorCTokenBalance(address) external view returns (uint256);

    function getPoolAvailableSDBalance() external view returns (uint256);

    function utilizerBalanceStored(address account) external view returns (uint256);

    function getDelegationRate() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function poolUtilization() external view returns (uint256);

    function getUtilizerLatestBalance(address _utilizer) external view returns (uint256);

    function getDelegatorLatestSDBalance(address _delegator) external view returns (uint256);

    function getLatestExchangeRate() external view returns (uint256);

    function utilizerData(address) external view returns (uint256 principal, uint256 utilizeIndex);

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
}
