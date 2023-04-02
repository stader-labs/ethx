// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IValidatorWithdrawalVault {
    // errors
    error InvalidRewardAmount();
    error CallerNotNodeRegistry();
    error InsufficientBalance();
    error TransferFailed();

    // events
    event ETHReceived(address indexed sender, uint256 amount);
    event DistributeRewardFailed(uint256 rewardAmount, uint256 rewardThreshold);
    event DistributedRewards(uint256 userShare, uint256 operatorShare, uint256 protocolShare);
    event SettledFunds(uint256 userShare, uint256 operatorShare, uint256 protocolShare);
    event UpdatedStaderConfig(address _staderConfig);

    function settleFunds() external;
}
