// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IOperatorRewardsCollector {
    //errors
    error InsufficientBalance();
    error WethTransferFailed();
    error SDTransferFailed();
    error PrincipalNotZeroed();
    error SDDebtNotCleared();
    error ZeroCustodyDelay();
    error CustodyDelayNotElapsed();
    error ZeroAmount();
    error TransferFailed();
    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);
    event UpdatedWethAddress(address indexed weth);
    event AdminSettledOperator(
        address indexed operator,
        uint256 interestSD,
        uint256 ethToTreasury,
        uint256 ethToOperator
    );
    event SetCustodyDelay(uint256 sweepToCustodyTimestamp);
    event SweptToCustody(address indexed asset, address indexed custody, uint256 amount);

    // methods

    function depositFor(address _receiver) external payable;

    function claim() external;

    function claimWithAmount(uint256 _amount) external;

    function claimLiquidation(address operator) external;

    function withdrawableInEth(address operator) external view returns (uint256);

    function getBalance(address operator) external view returns (uint256);

    function adminSettleOperator(address operator) external;

    function claimOnBehalf(address operator) external;

    function setCustodyDelay(uint256 _custodyDelay) external;

    function sweepToCustody(address _asset, address _custody) external;
}
