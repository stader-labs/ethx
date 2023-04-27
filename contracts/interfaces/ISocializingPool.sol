// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './IStaderOracle.sol';
import './IStaderConfig.sol';

interface ISocializingPool {
    // errors
    error ETHTransferFailed(address recipient, uint256 amount);
    error SDTransferFailed();
    error RewardAlreadyHandled();
    error RewardAlreadyClaimed(address operator, uint256 cycle);
    error InsufficientETHRewards();
    error InsufficientSDRewards();
    error InvalidAmount();
    error InvalidProof(uint256 cycle, address operator);
    error InvalidCycleIndex();
    error InvalidOperator();
    error InvalidPoolId();

    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event ETHReceived(address indexed sender, uint256 amount);
    event UpdatedStaderValidatorRegistry(address indexed staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address indexed staderOperatorRegistry);
    event OperatorRewardsClaimed(address indexed recipient, uint256 ethRewards, uint256 sdRewards);
    event OperatorRewardsUpdated(
        uint256 ethRewards,
        uint256 totalETHRewards,
        uint256 sdRewards,
        uint256 totalSDRewards
    );

    event UserETHRewardsTransferred(uint256 ethRewards);
    event ProtocolETHRewardsTransferred(uint256 ethRewards);

    // methods
    function handleRewards(RewardsData calldata _rewardsData) external;

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) external;

    // setters
    function updateStaderConfig(address _staderConfig) external;

    // getters
    function staderConfig() external view returns (IStaderConfig);

    function claimedRewards(address _user, uint256 _index) external view returns (bool);

    function totalOperatorETHRewardsRemaining() external view returns (uint256);

    function totalOperatorSDRewardsRemaining() external view returns (uint256);

    function initialBlock() external view returns (uint256);

    function poolId() external view returns (uint8);

    function verifyProof(
        uint256 _index,
        address _operator,
        uint256 _amountSD,
        uint256 _amountETH,
        bytes32[] calldata _merkleProof
    ) external view returns (bool);

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

    function getRewardCycleDetails(uint256 _index) external view returns (uint256 _startBlock, uint256 _endBlock);
}
