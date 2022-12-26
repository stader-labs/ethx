// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event TransferredToSSVPool(address indexed poolAddress, uint256 amount);
    event TransferredToStaderPool(address indexed poolAddress, uint256 amount);
    event UpdatedPoolWeights(uint256 staderSSVStakePoolWeight, uint256 staderManagedStakePoolWeight);
    event UpdatedSSVStakePoolAddress(address ssvStakePool);
    event UpdatedStaderStakePoolAddress(address staderStakePool);
    event UpdatedMinDepositLimit(uint256 amount);
    event UpdatedMaxDepositLimit(uint256 amount);
    event UpdatedEthXAddress(address account);
    event UpdatedEthXFeed(address account);
    event ToggledIsStakePaused(bool isStakePaused);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event UpdatedSocializingPoolAddress(address executionLayerRewardContract);
    event UpdatedFeePercentage(uint256 fee);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedStaderOracle(address oracle);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function receiveExecutionLayerRewards() external payable;
}
