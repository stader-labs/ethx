// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/ISDIncentiveController.sol';

/// @title SDIncentiveController
/// @notice This contract handles the distribution of reward tokens for a utility pool.
contract SDIncentiveController is ISDIncentiveController, AccessControlUpgradeable {
    // The emission rate of the reward tokens per block.
    uint256 public emissionPerBlock;

    // The block number of the last reward calculation.
    uint256 public lastUpdateBlockNumber;

    // The stored value of the reward per token, used to calculate rewards.
    uint256 public rewardPerTokenStored;

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
    /// @param _staderConfig The address of the Stader configuration contract.
    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);
        UtilLib.checkNonZeroAddress(_admin);

        staderConfig = IStaderConfig(_staderConfig);

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Claims the accrued rewards for an account.
    /// @param account The address of the account claiming rewards.
    function claim(address account) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        updateReward(account);

        uint256 reward = rewards[account];
        if (reward == 0) {
            revert NoRewardsToClaim();
        }
        rewards[account] = 0;
        IERC20(staderConfig.getStaderToken()).transfer(account, reward);

        emit RewardClaimed(account, reward);
    }

    /// @notice Updates the reward on deposit in the utility pool.
    /// @param account The account that made a deposit.
    function onDelegate(address account) external override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        updateReward(account);
    }

    /// @notice Calculates the current reward per token.
    /// @return The calculated reward per token.
    function rewardPerToken() public view returns (uint256) {
        uint256 totalSupply = ISDUtilityPool(staderConfig.getSDUtilityPool()).cTokenTotalSupply();
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((block.number - lastUpdateBlockNumber) * emissionPerBlock * 1e18) / totalSupply);
    }

    /// @notice Calculates the total accrued reward for an account.
    /// @param account The account to calculate rewards for.
    /// @return The total accrued reward for the account.
    function earned(address account) public view returns (uint256) {
        uint256 currentBalance = ISDUtilityPool(staderConfig.getSDUtilityPool()).delegatorCTokenBalance(account);
        uint256 currentRewardPerToken = rewardPerToken();

        return ((currentBalance * (currentRewardPerToken - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    /// @dev Internal function to update the reward state for an account.
    /// @param account The account to update the reward for.
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlockNumber = block.number;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /// @dev Emitted when a reward is claimed.
    /// @param user The user who claimed the reward.
    /// @param reward The amount of reward claimed.
    event RewardClaimed(address indexed user, uint256 reward);
}
