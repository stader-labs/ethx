// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IOperatorRewardsCollector {
    //errors
    error InsufficientBalance();
    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event Claimed(address indexed receiver, uint256 amount);
    event DepositedFor(address indexed sender, address indexed receiver, uint256 amount);

    // methods

    function depositFor(address _receiver) external payable;

    function claim() external;

    function claimFor(address account, uint256 amount) external;

    function claimLiquidation(
        uint256 liquidatorAmount,
        uint256 feeAmount,
        address liquidator
    ) external;

    function withdrawableInEth(address operator) external view returns (uint256);
}
