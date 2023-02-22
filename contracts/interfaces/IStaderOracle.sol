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
    @notice Submits the given ValidatorStatus for the public key at a specified block number.
    @param _pubkey The public key of the validator the status belong.
    @param _status The ValidatorStatus corresponding to the public key.
    */
    function submitStatus(bytes calldata _pubkey, ValidatorStatus _status) external;

    /**
    @notice Submits the whether the validator has a bad withdrawal.
    @param _pubkey The public key of the validator
    @param _isBadWithdrawal Whether the validator has a bad withdrawal
    */
    function submitValidatorWithdrawalValidity(bytes calldata _pubkey, bool _isBadWithdrawal) external;

    function getLatestReportableBlock() external view returns (uint256);
}
