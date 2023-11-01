// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../library/UtilLib.sol';
import '../interfaces/IStaderConfig.sol';

/// @title IncentiveController
/// @notice This contract handles the distribution of reward tokens for a lending pool.
contract IncentiveController is AccessControlUpgradeable {
    // The emission rate of the reward tokens per second.
    uint256 public emissionPerSecond;

    // The timestamp of the last reward calculation.
    uint256 public lastUpdateTimestamp;

    // The stored value of the reward per token, used to calculate rewards.
    uint256 public rewardPerTokenStored;

    // Reference to the lending pool token contract.
    IERC20 public lendingPoolToken;

    // Reference to the reward token contract.
    IERC20 public rewardToken;

    // Reference to the Stader configuration contract.
    IStaderConfig public staderConfig;

    // A mapping of accounts to their pending reward amounts.
    mapping(address => uint256) public rewards;

    // A mapping of accounts to the reward per token value at their last update.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with necessary addresses.
    /// @param _lendingPoolToken The address of the lending pool token contract.
    /// @param _staderConfig The address of the Stader configuration contract.
    /// @param _rewardToken The address of the reward token contract.
    function initialize(address _lendingPoolToken, address _staderConfig, address _rewardToken) external initializer {
        UtilLib.checkNonZeroAddress(_lendingPoolToken);
        UtilLib.checkNonZeroAddress(_staderConfig);
        UtilLib.checkNonZeroAddress(_rewardToken);

        lendingPoolToken = IERC20(_lendingPoolToken);
        staderConfig = IStaderConfig(_staderConfig);
        rewardToken = IERC20(_rewardToken);

        __AccessControl_init();
    }

    /// @notice Claims the accrued rewards for an account.
    /// @param account The address of the account claiming rewards.
    function claim(address account) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.LENDING_POOL_CONTRACT());

        updateReward(account);

        uint256 reward = rewards[account];
        require(reward > 0, "No rewards to claim.");
        rewards[account] = 0;
        rewardToken.transfer(account, reward);

        emit RewardClaimed(account, reward);
    }

    /// @notice Updates the reward on deposit in the lending pool.
    /// @param account The account that made a deposit.
    function onDeposit(address account) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.LENDING_POOL_CONTRACT());

        updateReward(account);
    }

    /// @notice Calculates the current reward per token.
    /// @return The calculated reward per token.
    function rewardPerToken() public view returns (uint256) {
        if (lendingPoolToken.totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (block.timestamp - lastUpdateTimestamp) * emissionPerSecond * 1e18 / lendingPoolToken.totalSupply()
        );
    }

    /// @notice Calculates the total accrued reward for an account.
    /// @param account The account to calculate rewards for.
    /// @return The total accrued reward for the account.
    function earned(address account) public view returns (uint256) {
        uint256 currentBalance = lendingPoolToken.balanceOf(account);
        uint256 currentRewardPerToken = rewardPerToken();

        return (currentBalance * (currentRewardPerToken - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    /// @dev Internal function to update the reward state for an account.
    /// @param account The account to update the reward for.
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTimestamp = block.timestamp;

        if(account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /// @dev Emitted when a reward is claimed.
    /// @param user The user who claimed the reward.
    /// @param reward The amount of reward claimed.
    event RewardClaimed(address indexed user, uint256 reward);
}
