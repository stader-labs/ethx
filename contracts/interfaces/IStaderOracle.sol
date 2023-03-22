// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

/// @title RewardsData
/// @notice This struct holds rewards merkleRoot and rewards split
struct RewardsData {
    /// @notice The block number when the rewards data was last updated
    uint256 lastUpdatedBlockNumber;
    /// @notice The index of merkle tree or rewards cycle
    uint256 index;
    /// @notice The merkle root hash
    bytes32 merkleRoot;
    /// @notice pool id of operators
    uint8 poolId;
    /// @notice operator ETH rewards for index cycle
    uint256 operatorETHRewards;
    /// @notice user ETH rewards for index cycle
    uint256 userETHRewards;
    /// @notice protocol ETH rewards for index cycle
    uint256 protocolETHRewards;
    /// @notice operator SD rewards for index cycle
    uint256 operatorSDRewards;
}

/// @title ExchangeRate
/// @notice This struct holds data related to the exchange rate between ETH and ETHX.
struct ExchangeRate {
    /// @notice The block number when the exchange rate was last updated.
    uint256 lastUpdatedBlockNumber;
    /// @notice The total balance of Ether (ETH) in the system.
    uint256 totalETHBalance;
    /// @notice The total balance of staked Ether (ETH) in the system.
    uint256 totalStakingETHBalance;
    /// @notice The total supply of the liquid staking token (ETHX) in the system.
    uint256 totalETHXSupply;
}

/// @title ValidatorStats
/// @notice This struct holds statistics related to validators in the beaconchain.
struct ValidatorStats {
    /// @notice The block number when the validator stats was last updated.
    uint256 lastUpdatedBlockNumber;
    /// @notice The total balance of all active validators.
    uint128 activeValidatorsBalance;
    /// @notice The total balance of all exited validators.
    uint128 exitedValidatorsBalance;
    /// @notice The total balance of all slashed validators.
    uint128 slashedValidatorsBalance;
    /// @notice The number of currently active validators.
    uint32 activeValidatorsCount;
    /// @notice The number of validators that have exited.
    uint32 exitedValidatorsCount;
    /// @notice The number of validators that have been slashed.
    uint32 slashedValidatorsCount;
}

interface IStaderOracle {
    // Events
    event BalancesSubmitted(
        address indexed from,
        uint256 block,
        uint256 totalEth,
        uint256 stakingEth,
        uint256 ethxSupply,
        uint256 time
    );
    event BalancesUpdated(uint256 block, uint256 totalEth, uint256 stakingEth, uint256 ethxSupply, uint256 time);
    event TrustedNodeAdded(address indexed node);
    event TrustedNodeRemoved(address indexed node);
    event SocializingRewardsMerkleRootSubmitted(address indexed node, uint256 index, bytes32 merkleRoot, uint256 block);
    event SocializingRewardsMerkleRootUpdated(uint256 index, bytes32 merkleRoot, uint256 block);
    event UpdateFrequencyUpdated(uint256 updateFrequency);
    event ValidatorStatsSubmitted(
        address indexed from,
        uint256 block,
        uint256 activeValidatorsBalance,
        uint256 exitedValidatorsBalance,
        uint256 slashedValidatorsBalance,
        uint256 activeValidatorsCount,
        uint256 exitedValidatorsCount,
        uint256 slashedValidatorsCount,
        uint256 time
    );
    event ValidatorStatsUpdated(
        uint256 block,
        uint256 activeValidatorsBalance,
        uint256 exitedValidatorsBalance,
        uint256 slashedValidatorsBalance,
        uint256 activeValidatorsCount,
        uint256 exitedValidatorsCount,
        uint256 slashedValidatorsCount,
        uint256 time
    );

    function getExchangeRate() external view returns (ExchangeRate memory);

    function getValidatorStats() external view returns (ValidatorStats memory);

    // The frequency in blocks at which network updates should be submitted by trusted nodes
    function updateFrequency() external view returns (uint256);

    function trustedNodesCount() external view returns (uint256);

    function isTrustedNode(address) external view returns (bool);

    function addTrustedNode(address _nodeAddress) external;

    function removeTrustedNode(address _nodeAddress) external;

    function setUpdateFrequency(uint256 _balanceUpdateFrequency) external;

    /**
    @dev Submits the given balances for a specified block number.
    @param _exchangeRate The exchange rate to submit.
    */
    function submitBalances(ExchangeRate calldata _exchangeRate) external;

    /**
    @notice Submits the root of the merkle tree containing the socializing rewards.
    sends user ETH Rewrds to SSPM
    sends protocol ETH Rewards to stader treasury
    @param _rewardsData contains rewards merkleRoot and rewards split
    */
    function submitSocializingRewardsMerkleRoot(RewardsData calldata _rewardsData) external;

    /*
     * @notice Submit validator stats for a specific block.
     * @dev This function can only be called by trusted nodes.
     * @param _validatorStats The validator stats to submit.
     *
     * Function Flow:
     * 1. Validates that the submission is for a past block and not a future one.
     * 2. Validates that the submission is for a block higher than the last block number with updated counts.
     * 3. Generates submission keys using the input parameters.
     * 4. Validates that this is not a duplicate submission from the same node.
     * 5. Updates the submission count for the given counts.
     * 6. Emits a ValidatorCountsSubmitted event with the submitted data.
     * 7. If the submission count reaches a majority (trustedNodesCount / 2 + 1), checks whether the counts are not already updated,
     *    then updates the validator counts, and emits a CountsUpdated event.
     */
    function submitValidatorStats(ValidatorStats calldata _validatorStats) external;

    function getLatestReportableBlock() external view returns (uint256);
}
