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

struct MissedAttestationPenaltyData {
    /// @notice count of validator missing attestation penalty
    uint16 keyCount;
    /// @notice The block number when the missed attestation penalty data was last updated
    uint256 lastUpdatedBlockNumber;
    /// @notice The index of missed attestation penalty data
    uint256 index;
    /// @notice page number of the the data
    uint256 pageNumber;
    /// @bytes missed attestation validator's concatenated pubkey
    bytes pubkeys;
}

interface IStaderOracle {
    //Error
    error NodeAlreadyTrusted();
    error NodeNotTrusted();
    error ZeroFrequency();
    error FrequencyUnchanged();
    error BalancesSubmittedForFutureBlock();
    error NetworkBalancesSetForEqualOrHigherBlock();
    error InvalidNetworkBalances();
    error DuplicateSubmissionFromNode();
    error DataSubmittedForFutureBlock();
    error InvalidMerkleRootIndex();
    error InvalidData();
    error DataAlreadyReported();
    error InvalidPubkeyLength();
    error NotATrustedNode();

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
    event SocializingRewardsMerkleRootSubmitted(address indexed node, uint256 index, bytes32 merkleRoot, uint256 block);
    event SocializingRewardsMerkleRootUpdated(uint256 index, bytes32 merkleRoot, uint256 block);
    event MissedAttestationPenaltySubmitted(address indexed node, uint256 index, uint256 pageNumber, uint256 block);
    event MissedAttestationPenaltyUpdated(uint256 index, uint256 block);

    // The block number which balances are current for
    function lastBlockNumberBalancesUpdated() external view returns (uint256);

    // The current network total ETH balance
    function totalETHBalance() external view returns (uint256);

    // The current network staking ETH balance
    function totalStakingETHBalance() external view returns (uint256);

    // The current network total ETHX supply
    function totalETHXSupply() external view returns (uint256);

    // The root of the merkle tree containing the socializing rewards of operator
    function socializingRewardsMerkleRoot(uint256) external view returns (bytes32);

    // The last updated merkle tree index
    function getCurrentRewardsIndex() external view returns (uint256);

    // The frequency in blocks at which network balances should be submitted by trusted nodes
    function balanceUpdateFrequency() external view returns (uint256);

    function trustedNodesCount() external view returns (uint256);

    function isTrustedNode(address) external view returns (bool);

    function missedAttestationPenalty(bytes32 pubkey) external view returns (uint16);

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
    @notice Submits the root of the merkle tree containing the socializing rewards.
    sends user ETH Rewrds to SSPM
    sends protocol ETH Rewards to stader treasury
    @param _rewardsData contains rewards merkleRoot and rewards split
    */
    function submitSocializingRewardsMerkleRoot(RewardsData calldata _rewardsData) external;

    function getLatestReportableBlock() external view returns (uint256);
}
