// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

interface INodeELRewardVault {
    event ETHReceived(uint256 amount);
    event Withdrawal(uint256 protocolAmount, uint256 operatorAmount, uint256 userAmount);

    function withdraw() external;
}
