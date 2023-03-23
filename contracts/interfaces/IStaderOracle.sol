// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

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
    @param _block The block number at which the balances are being submitted.
    @param _totalEth The total amount of ETH in the system at the specified block number.
    @param _stakingEth The amount of ETH currently staked in the beaconchain at the specified block number.
    @param _ethxSupply The total supply of ETHX tokens at the specified block number.
    */
    function submitBalances(
        uint256 _block,
        uint256 _totalEth,
        uint256 _stakingEth,
        uint256 _ethxSupply
    ) external;

    /**
     * @notice Submit validator stats for a specific block.
     * @dev This function can only be called by trusted nodes.
     * @param _blockNumber The block number for which validator stats are being submitted.
     * @param _activeValidatorsBalance The total balance of all active validators.
     * @param _exitedValidatorsBalance The total balance of all exited validators.
     * @param _slashedValidatorsBalance The total balance of all slashed validators.
     * @param _activeValidatorsCount The number of active validators at the given block on the beaconchain.
     * @param _exitedValidatorsCount The number of exited validators at the given block on the beaconchain.
     * @param _slashedValidatorsCount The number of slashed validators at the given block on the beaconchain.
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
    function submitValidatorStats(
        uint256 _blockNumber,
        uint128 _activeValidatorsBalance,
        uint128 _exitedValidatorsBalance,
        uint128 _slashedValidatorsBalance,
        uint32 _activeValidatorsCount,
        uint32 _exitedValidatorsCount,
        uint32 _slashedValidatorsCount
    ) external;

    function getLatestReportableBlock() external view returns (uint256);
}
