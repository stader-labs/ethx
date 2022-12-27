// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface ISocializingPoolContract {
    event ETHReceived(uint256 amount);
    event UpdatedStaderPoolManager(address staderStakePoolManager);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedFeePercentage(uint256 feePercentage);
}
