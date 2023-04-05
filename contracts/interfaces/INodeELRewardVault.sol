// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

interface INodeELRewardVault {
    // errors
    error ETHTransferFailed();

    // events
    event ETHReceived(address indexed sender, uint256 amount);
    event Withdrawal(uint256 protocolAmount, uint256 operatorAmount, uint256 userAmount);
    event UpdatedStaderConfig(address staderConfig);

    function withdraw() external;
}
