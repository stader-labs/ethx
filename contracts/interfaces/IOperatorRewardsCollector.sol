// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IOperatorRewardsCollector {
    //errors
    error InsufficientBalance();
    error WethTransferFailed();
    error GracePeriodActive();
    error GraceAlreadySet();
    error InvalidGracePeriod();
    error PrincipalNotZeroed();
    error SDDebtNotCleared();
    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);
    event UpdatedWethAddress(address indexed weth);
    event SunsetGracePeriodSet(uint256 sunsetGracePeriodEnd);
    event AdminSettledOperator(
        address indexed operator,
        uint256 interestSD,
        uint256 ethToTreasury,
        uint256 ethToOperator
    );
    event SweptToCustody(address indexed custody, uint256 amount);

    // methods

    function depositFor(address _receiver) external payable;

    function claim() external;

    function claimWithAmount(uint256 _amount) external;

    function claimLiquidation(address operator) external;

    function withdrawableInEth(address operator) external view returns (uint256);

    function getBalance(address operator) external view returns (uint256);

    function setSunsetGracePeriodEnd(uint256 _sunsetGracePeriodEnd) external;

    function adminSettleOperator(address operator) external;

    function claimOnBehalf(address operator) external;

    function sweepToCustody(address custody) external;
}
