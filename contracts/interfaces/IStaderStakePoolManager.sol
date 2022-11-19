// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IStaderStakePoolManager {
    event Deposited(address indexed sender, uint256 amount, address referral);
    event TransferredToSSVPool(address indexed poolAddress, uint256 amount);
    event TransferredToStaderPool(address indexed poolAddress, uint256 amount);
    event UpdatedPoolWeights(
        uint256 staderSSVStakePoolWeight,
        uint256 staderManagedStakePoolWeight
    );
    event UpdatedSSVStakePoolAddress(address ssvStakePool);
    event UpdatedStaderStakePoolAddress(address staderStakePool);
    event UpdatedMinDeposit(uint256 amount);
    event UpdatedMaxDeposit(uint256 amount);
    event UpdatedEthXAddress(address account);
    event UpdatedEthXFeed(address account);
    event ToggledIsStakePaused(bool isStakePaused);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event UpdatedELRewardContract(address executionLayerRewardContract);
    event UpdatedFeePercentage(uint256 fee);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);

    function receiveExecutionLayerRewards() external payable;
}
