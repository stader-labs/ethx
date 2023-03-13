// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

interface INodeELRewardVault {
    event ETHReceived(uint256 amout);
    event Withdrawal(uint256 protocolAmount, uint256 operatorAmount, uint256 userAmount);

    function withdraw() external;

    function calculateProtocolShare() external view returns (uint256);

    function calculateOperatorShare() external view returns (uint256);

    function calculateUserShare() external view returns (uint256);
}
