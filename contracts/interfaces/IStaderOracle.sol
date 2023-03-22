// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

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
    event BalanceUpdateFrequencyUpdated(uint256 balanceUpdateFrequency);
    event ValidatorCountsSubmitted(
        address indexed from,
        uint256 block,
        uint256 activeValidatorsCount,
        uint256 exitedValidatorsCount,
        uint256 slashedValidatorsCount,
        uint256 time
    );
    event ValidatorCountsUpdated(
        uint256 block,
        uint256 activeValidatorsCount,
        uint256 exitedValidatorsCount,
        uint256 slashedValidatorsCount,
        uint256 time
    );

    // The block number which balances are current for
    function lastBlockNumberBalancesUpdated() external view returns (uint256);

    // The current network total ETH balance
    function totalETHBalance() external view returns (uint256);

    // The current network staking ETH balance
    function totalStakingETHBalance() external view returns (uint256);

    // The current network total ETHX supply
    function totalETHXSupply() external view returns (uint256);

    // The frequency in blocks at which network balances should be submitted by trusted nodes
    function balanceUpdateFrequency() external view returns (uint256);

    function activeValidatorsCount() external view returns (uint256);

    function exitedValidatorsCount() external view returns (uint256);

    function slashedValidatorsCount() external view returns (uint256);

    function lastBlockNumberCountsUpdated() external view returns (uint256);

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
     * @notice Submit validator counts for a specific block.
     * @dev This function can only be called by trusted nodes.
     * @param _block The block number for which validator counts are being submitted.
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
    function submitValidatorCounts(
        uint256 _block,
        uint256 _activeValidatorsCount,
        uint256 _exitedValidatorsCount,
        uint256 _slashedValidatorsCount
    ) external;

    function getLatestReportableBlock() external view returns (uint256);
}
