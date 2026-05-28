// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IOperatorRewardsCollector {
    //errors
    error InsufficientBalance();
    error WethTransferFailed();
    error AssetCustodied();
    error ZeroCustodyDelay();
    error ZeroAddress();
    error ZeroAmount();
    error CustodyDelayNotElapsed();
    error TransferFailed();
    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);
    event UpdatedWethAddress(address indexed weth);
    event SetCustodyDelay(uint256 sweepToCustodyTimestamp);
    event SweptToCustody(address asset, address custody, uint256 amount);
    event AdminSettledOperator(address indexed operator);

    // methods

    function depositFor(address _receiver) external payable;

    function claim() external;

    function claimWithAmount(uint256 _amount) external;

    function claimLiquidation(address operator) external;

    function withdrawableInEth(address operator) external view returns (uint256);

    function getBalance(address operator) external view returns (uint256);

    function assetCustodied() external view returns (bool);

    function sweepToCustodyTimestamp() external view returns (uint256);

    function adminSettleOperator(address op) external;

    function setCustodyDelay(uint256 _custodyDelay) external;

    function sweepToCustody(address _asset, address _custody) external;
}
