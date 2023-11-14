// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ISDUtilityPool {
    error SDTransferFailed();
    error SDUtilizeLimitReached();
    error InsufficientPoolBalance();
    error AccrualBlockNumberNotLatest();

    event UpdatedStaderConfig(address indexed _staderConfig);
    event Delegated(address indexed delegator, uint256 sdAmount, uint256 sdXToMint);
    event Redeemed(address indexed delegator, uint256 sdAmount, uint256 sdXAmount);
    event Repaid(address indexed utilizer, uint256 repayAmount);

    event AccruedFees(uint256 feeAccumulated, uint256 totalProtocolFee, uint256 totalUtilizedSD);

    function delegate(uint256 sdAmount) external;

    // function requestWithdraw(uint256 sdAmount) external return (uint);

    // function claim(uint256 requestId) external;

    function redeem(uint256 sdXAmount) external;

    function utilizeWhileAddingKeys(
        address operator,
        uint256 utilizeAmount,
        uint256 nonTerminalKeyCount
    ) external;

    function repay(uint256 repayAmount) external;

    function repayOnBehalf(address utilizer, uint256 repayAmount) external;

    function accrueFee() external;

    function utilizeBalanceCurrent(address account) external returns (uint256);

    function utilizeBalanceStored(address account) external view returns (uint256);

    function poolUtilization() external view returns (uint256);

    function getDelegationRate() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getPoolSDBalance() external view returns (uint256);
}
