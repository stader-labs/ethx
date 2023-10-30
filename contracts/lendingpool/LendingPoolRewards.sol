// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';

contract LendingPoolRewards {
    uint256 public emissionPerSecond;
    uint256 public lastUpdateTimestamp;
    uint256 public index;
    address public lendingPool;
    struct UserState {
        uint256 lastUpdateTimestamp;
        uint256 pendingRewards;
        uint256 lastIndex;
    }
    mapping(address => uint256) public users;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Initializes the contract
    * @param _emissionPerSecond The emission per second of the distribution
    * @param _assets The assets to be distributed
    * @param _lendingPool The address of the LendingPool contract
    **/
    */
    function initialize(address _lendingPool) external initializer {
        UtilLib.checkNonZeroAddress(_lendingPool);

        emissionPerSecond = 1;
        lastUpdateTimestamp = block.timestamp;
        index = 1e18;
        lendingPool = _lendingPool;

        __AccessControl_init();
    }

    function onChange(address user, uint256 newBalance) external {
        require(msg.sender == lendingPool, "Only the lending pool can call this function");

        UserState storage userState = users[user];
        userState.pendingRewards = _getRewardsBalance(user);
        userState.lastUpdateTimestamp = block.timestamp;
        userState.lastIndex = index;
    }

    /**
    * @dev Returns the total of rewards of an user, already accrued + not yet accrued
    * @param user The address of the user
    * @return The rewards
    **/
    function getRewardsBalance(address user)
        external
        view
        override
        returns (uint256)
    {
        uint256 unclaimedRewards = _usersUnclaimedRewards[user];

        userState[i].underlyingAsset = assets[i];
        (userState[i].stakedByUser, userState[i].totalStaked) = IAToken(assets[i])
            .getScaledUserBalanceAndSupply(user);
    
        unclaimedRewards = unclaimedRewards.add(_getUnclaimedRewards(user, userState));
        return unclaimedRewards;
    }

    /**
    * @dev Calculates the next value of an specific distribution index, with validations
    * @param currentIndex Current index of the distribution
    * @param emissionPerSecond Representing the total rewards distributed per second per asset unit, on the distribution
    * @param lastUpdateTimestamp Last moment this distribution was updated
    * @param totalBalance of tokens considered for the distribution
    * @return The new index.
    **/
    function _getAssetIndex(
      uint256 currentIndex,
      uint256 emissionPerSecond,
      uint128 lastUpdateTimestamp,
      uint256 totalBalance
    ) internal view returns (uint256) {
      if (
        emissionPerSecond == 0 ||
        totalBalance == 0 ||
        lastUpdateTimestamp == block.timestamp ||
        lastUpdateTimestamp >= DISTRIBUTION_END
      ) {
        return currentIndex;
      }

      uint256 currentTimestamp =
        block.timestamp > DISTRIBUTION_END ? DISTRIBUTION_END : block.timestamp;
      uint256 timeDelta = currentTimestamp.sub(lastUpdateTimestamp);
      return
        emissionPerSecond.mul(timeDelta).mul(10**uint256(PRECISION)).div(totalBalance).add(
          currentIndex
        );
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if(account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function updateRewardSnapshot() internal updateReward(address(0)) {
        // Create a new snapshot with the current state.
        rewardSnapshots.push(Snapshot({
            time: block.timestamp,
            rewardPerToken: rewardPerTokenStored
        }));
    }

    function rewardPerToken() public view returns (uint256) {
        if (cToken.totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (block.timestamp - lastUpdateTime) * rewardRatePerSecond * 1e18 / cToken.totalSupply()
        );
    }

    function earned(address account) public view returns (uint256) {
        uint256 currentBalance = cToken.balanceOf(account);
        uint256 currentRewardPerToken = rewardPerToken();
        return (currentBalance * (currentRewardPerToken - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    function claimReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim.");
        rewards[msg.sender] = 0;
        // Transfer the rewards to the user.
        emit RewardClaimed(msg.sender, reward);
    }

    event RewardClaimed(address indexed user, uint256 reward);
}