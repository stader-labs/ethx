// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/ISDIncentiveController.sol';

/// @title SDIncentiveController
/// @notice This contract handles the distribution of reward tokens for the utility pool.
contract SDIncentiveController is ISDIncentiveController, AccessControlUpgradeable {
    uint256 public constant DECIMAL = 1e18;

    // The emission rate of the reward tokens per block.
    uint256 public emissionPerBlock;

    // The block number of the end of the reward period.
    uint256 public rewardEndBlock;

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
    function claim(address account) external override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        updateReward(account);

        uint256 reward = rewards[account];
        rewards[account] = 0;
        if (reward > 0) IERC20(staderConfig.getStaderToken()).transfer(account, reward);

        emit RewardClaimed(account, reward);
    }

    /// @notice Updates the reward for the account, expected to be called before delegate or after withdraw.
    /// @param account The account that delegated or withdrew.
    function updateRewardForAccount(address account) external override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        updateReward(account);
    }

    /// @notice Updates the address of staderConfig
    /// @param _staderConfig The new address of staderConfig
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /// @notice Updates the emission rate of the reward tokens per block.
    /// @param newEmissionRate The new emission rate per block.
    function updateEmissionRate(uint256 newEmissionRate) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEmissionRate == 0) revert InvalidEmissionRate();
        emissionPerBlock = newEmissionRate;
        emit EmissionRateUpdated(newEmissionRate);
    }

    /// @notice Updates the end block of the reward period.
    /// @param _newEndBlock The new end block.
    function updateEndBlock(uint256 _newEndBlock) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newEndBlock <= block.number) revert InvalidEndBlock();
        rewardEndBlock = _newEndBlock;
        emit RewardEndBlockUpdated(_newEndBlock);
    }

    /// @notice Calculates the current reward per token.
    /// @return The calculated reward per token.
    function rewardPerToken() public view override returns (uint256) {
        if (block.number >= rewardEndBlock) {
            return rewardPerTokenStored;
        }

        uint256 totalSupply = ISDUtilityPool(staderConfig.getSDUtilityPool()).cTokenTotalSupply();
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((block.number - lastUpdateBlockNumber) * emissionPerBlock * DECIMAL) / totalSupply);
    }

    /// @notice Calculates the total accrued reward for an account.
    /// @param account The account to calculate rewards for.
    /// @return The total accrued reward for the account.
    function earned(address account) public view override returns (uint256) {
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(staderConfig.getSDUtilityPool());
        uint256 currentBalance = sdUtilityPool.delegatorCTokenBalance(account) +
            sdUtilityPool.delegatorWithdrawRequestedCTokenCount(account);
        uint256 currentRewardPerToken = rewardPerToken();

        return
            ((currentBalance * (currentRewardPerToken - userRewardPerTokenPaid[account])) / DECIMAL) + rewards[account];
    }

    /// @dev Internal function to update the reward state for an account.
    /// @param account The account to update the reward for.
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlockNumber = block.number;

        // If the account is not zero, update the reward for the account.
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }

        emit RewardUpdated(account, rewards[account]);
    }
}
