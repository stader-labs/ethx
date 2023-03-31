// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IValidatorWithdrawalVault {
    // errors
    error InvalidRewardAmount();

    // events
    event ETHReceived(address indexed sender, uint256 amount);
    event DistributeRewardFailed(uint256 rewardAmount, uint256 rewardThreshold);
}