// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './IStaderOracle.sol';

interface ISocializingPool {
    // errors
    error ETHTransferFailed(address recipient, uint256 amount);
    error RewardAlreadyHandled();
    error RewardAlreadyClaimed(address operator, uint256 cycle);
    error InsufficientETHRewards();
    error InsufficientSDRewards();
    error InvalidAmount();
    error InvalidProof(uint256 cycle, address operator);

    // events
    event ETHReceived(address indexed sender, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

    function getRewardDetails()
        external
        view
        returns (
            uint256 currentIndex,
            uint256 currentStartBlock,
            uint256 currentEndBlock,
            uint256 nextIndex,
            uint256 nextStartBlock,
            uint256 nextEndBlock
        );

    function handleRewards(RewardsData calldata _rewardsData) external;

    function claimedRewards(address _user, uint256 _index) external view returns (bool);

    function totalELRewardsCollected() external view returns (uint256);

    function totalOperatorETHRewardsRemaining() external view returns (uint256);

    function totalOperatorSDRewardsRemaining() external view returns (uint256);

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        address operatorRewardsAddr
    ) external;
}
