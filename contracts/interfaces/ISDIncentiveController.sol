// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./IStaderConfig.sol";

interface ISDIncentiveController {
    //errors
    error NoRewardsToClaim();
    error InvalidEmissionRate();
    error InvalidEndBlock();
    error InvalidRewardAmount();
    error ExistingRewardPeriod();
    error SDTransferFailed();

    // events
    /// @dev Emitted when the Stader configuration contract is updated.
    /// @param staderConfig The new Stader configuration contract.
    event UpdatedStaderConfig(address staderConfig);
    /// @dev Emitted when the emission rate of rewards is updated.
    /// @param newEmissionRate The new emission rate that was set.
    event EmissionRateUpdated(uint256 newEmissionRate);
    /// @dev Emitted when a reward is claimed.
    /// @param user The user who claimed the reward.
    /// @param reward The amount of reward claimed.
    event RewardClaimed(address indexed user, uint256 reward);
    /// @dev Emitted when a reward is updated.
    /// @param user The user whose reward was updated.
    /// @param reward The new reward amount.
    event RewardUpdated(address indexed user, uint256 reward);
    /// @dev Emitted when the reward end block is updated.
    /// @param newRewardEndBlock The new reward end block that was set.
    event RewardEndBlockUpdated(uint256 newRewardEndBlock);

    // functions
    function start(uint256 rewardAmount, uint256 duration) external;

    function claim(address account) external;

    function updateRewardForAccount(address account) external;

    function updateStaderConfig(address _staderConfig) external;

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);
}
