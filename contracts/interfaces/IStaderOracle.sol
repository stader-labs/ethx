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

    // The block number which balances are current for
    function lastBlockNumberBalancesUpdated() external view returns (uint256);

    // The block number which statuses are current for
    function lastBlockNumberStatusUpdated() external view returns (uint256);

    // The current network total ETH balance
    function totalETHBalance() external view returns (uint256);

    // The current network staking ETH balance
    function totalStakingETHBalance() external view returns (uint256);

    // The current network total ETHX supply
    function totalETHXSupply() external view returns (uint256);

    // The frequency in blocks at which network balances should be submitted by trusted nodes
    function balanceUpdateFrequency() external view returns (uint256);

    function trustedNodesCount() external view returns (uint256);

    function isTrustedNode(address) external view returns (bool);

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
    @notice Submits the given ValidatorStatuses for a batch of public keys at a specified block number.
    @param _block The block number at which the statuses are being submitted.
    @param _pubkeys An array of public keys to which the statuses belong.
    @param _status An array of ValidatorStatuses corresponding to the public keys.
    */
    function submitStatus(
        uint256 _block,
        bytes[] calldata _pubkeys,
        ValidatorStatus[] calldata _status
    ) external;

    /**
    @notice Submits the whether the validator has a bad withdrawal.
    @param _pubkey The public key of the validator
    @param _isBadWithdrawal Whether the validator has a bad withdrawal
    */
    function submitValidatorWithdrawalValidity(bytes calldata _pubkey, bool _isBadWithdrawal) external;

    function getLatestReportableBlock() external view returns (uint256);
}
