// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/ISocializingPool.sol';
import './library/Address.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable {
    RewardsData public rewardsData;

    MissedAttestationPenaltyData public missedAttestationPenaltyData;

    uint64 private constant VALIDATOR_PUBKEY_LENGTH = 48;

    IStaderConfig public staderConfig;
    /// @inheritdoc IStaderOracle
    uint256 public override lastBlockNumberBalancesUpdated;
    /// @inheritdoc IStaderOracle
    uint256 public override totalETHBalance;
    /// @inheritdoc IStaderOracle
    uint256 public override totalStakingETHBalance;
    /// @inheritdoc IStaderOracle
    uint256 public override totalETHXSupply;
    /// @inheritdoc IStaderOracle
    uint256 public override balanceUpdateFrequency;
    /// @inheritdoc IStaderOracle
    uint256 public override trustedNodesCount;

    // indicate the health of protocol on beacon chain
    // set to true by oracle if heavy slashing on protocol on beacon chain
    bool public override safeMode;

    /// @inheritdoc IStaderOracle
    mapping(uint256 => bytes32) public override socializingRewardsMerkleRoot;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;
    mapping(bytes32 => uint16) public override missedAttestationPenalty;
    // mapping of report index, report pageNumber with trusted node address
    mapping(uint256 => mapping(uint256 => address)) private MissedAttestationDataByTrustedNode;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();

        balanceUpdateFrequency = 7200; // 24 hours

        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /// @inheritdoc IStaderOracle
    function addTrustedNode(address _nodeAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_nodeAddress);
        if (isTrustedNode[_nodeAddress]) revert NodeAlreadyTrusted();
        isTrustedNode[_nodeAddress] = true;
        trustedNodesCount++;

        emit TrustedNodeAdded(_nodeAddress);
    }

    /// @inheritdoc IStaderOracle
    function removeTrustedNode(address _nodeAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_nodeAddress);
        if (!isTrustedNode[_nodeAddress]) revert NodeNotTrusted();
        isTrustedNode[_nodeAddress] = false;
        trustedNodesCount--;

        emit TrustedNodeRemoved(_nodeAddress);
    }

    function setUpdateFrequency(uint256 _balanceUpdateFrequency) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_balanceUpdateFrequency == 0) revert ZeroFrequency();
        if (_balanceUpdateFrequency == balanceUpdateFrequency) revert FrequencyUnchanged();
        balanceUpdateFrequency = _balanceUpdateFrequency;

        emit BalanceUpdateFrequencyUpdated(_balanceUpdateFrequency);
    }

    /// @inheritdoc IStaderOracle
    function submitBalances(
        uint256 _block,
        uint256 _totalEth,
        uint256 _stakingEth,
        uint256 _ethxSupply
    ) external override trustedNodeOnly {
        // Check block
        if (_block >= block.number) revert BalancesSubmittedForFutureBlock();
        if (_block <= lastBlockNumberBalancesUpdated) revert NetworkBalancesSetForEqualOrHigherBlock();
        // Check balances
        if (_stakingEth > _totalEth) revert InvalidNetworkBalances();
        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(msg.sender, _block, _totalEth, _stakingEth, _ethxSupply)
        );
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_block, _totalEth, _stakingEth, _ethxSupply));
        // Check & update node submission status
        if (nodeSubmissionKeys[nodeSubmissionKey]) revert DuplicateSubmissionFromNode();
        nodeSubmissionKeys[nodeSubmissionKey] = true;
        submissionCountKeys[submissionCountKey]++;
        uint8 submissionCount = submissionCountKeys[submissionCountKey];
        // Emit balances submitted event
        emit BalancesSubmitted(msg.sender, _block, _totalEth, _stakingEth, _ethxSupply, block.timestamp);
        if (submissionCount >= trustedNodesCount / 2 + 1) {
            // Update balances
            lastBlockNumberBalancesUpdated = _block;
            totalETHBalance = _totalEth;
            totalStakingETHBalance = _stakingEth;
            totalETHXSupply = _ethxSupply;
            // Emit balances updated event
            emit BalancesUpdated(_block, _totalEth, _stakingEth, _ethxSupply, block.timestamp);
        }
    }

    // Returns the latest block number that oracles should be reporting balances for
    function getLatestReportableBlock() external view override returns (uint256) {
        // Calculate the last reportable block based on update frequency
        return (block.number * balanceUpdateFrequency) / balanceUpdateFrequency;
    }

    /// @notice submits merkle root and handles reward
    /// sends user rewards to Stader Stake Pool Manager
    /// sends protocol rewards to stader treasury
    /// updates operator reward balances on socializing pool
    /// @param _rewardsData contains rewards merkleRoot and rewards split info
    /// @dev _rewardsData.index should not be zero
    function submitSocializingRewardsMerkleRoot(RewardsData calldata _rewardsData) external override trustedNodeOnly {
        if (_rewardsData.lastUpdatedBlockNumber < block.number) revert DataSubmittedForFutureBlock();

        if (_rewardsData.index <= rewardsData.index) revert InvalidMerkleRootIndex();

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _rewardsData.index,
                _rewardsData.merkleRoot,
                _rewardsData.operatorETHRewards,
                _rewardsData.userETHRewards,
                _rewardsData.protocolETHRewards,
                _rewardsData.operatorSDRewards
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _rewardsData.index,
                _rewardsData.merkleRoot,
                _rewardsData.operatorETHRewards,
                _rewardsData.userETHRewards,
                _rewardsData.protocolETHRewards,
                _rewardsData.operatorSDRewards
            )
        );

        uint8 submissionCount = _getSubmissionCount(nodeSubmissionKey, submissionCountKey);
        // Emit merkle root submitted event
        emit SocializingRewardsMerkleRootSubmitted(
            msg.sender,
            _rewardsData.index,
            _rewardsData.merkleRoot,
            block.number
        );

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            // Update merkle root
            socializingRewardsMerkleRoot[_rewardsData.index] = _rewardsData.merkleRoot;
            rewardsData = _rewardsData;

            address socializingPool = IPoolFactory(staderConfig.getPoolFactory()).getSocializingPoolAddress(
                _rewardsData.poolId
            );
            ISocializingPool(socializingPool).handleRewards(_rewardsData);

            emit SocializingRewardsMerkleRootUpdated(_rewardsData.index, _rewardsData.merkleRoot, block.number);
        }
    }

    /**
     * @notice store the missed attestation penalty strike on validator
     * @dev _missedAttestationPenaltyData.index should not be zero
     * @param _missedAttestationPenaltyData missed attestation penalty data
     */
    function submitMissedAttestationPenalties(MissedAttestationPenaltyData calldata _missedAttestationPenaltyData)
        external
        trustedNodeOnly
    {
        if (_missedAttestationPenaltyData.lastUpdatedBlockNumber >= block.number) revert DataSubmittedForFutureBlock();

        if (
            _missedAttestationPenaltyData.keyCount * VALIDATOR_PUBKEY_LENGTH ==
            _missedAttestationPenaltyData.pubkeys.length
        ) revert InvalidData();

        if (
            MissedAttestationDataByTrustedNode[_missedAttestationPenaltyData.index][
                _missedAttestationPenaltyData.pageNumber
            ] != address(0)
        ) revert DataAlreadyReported();

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _missedAttestationPenaltyData.index,
                _missedAttestationPenaltyData.pageNumber,
                _missedAttestationPenaltyData.pubkeys
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _missedAttestationPenaltyData.index,
                _missedAttestationPenaltyData.pageNumber,
                _missedAttestationPenaltyData.pubkeys
            )
        );

        MissedAttestationDataByTrustedNode[_missedAttestationPenaltyData.index][
            _missedAttestationPenaltyData.pageNumber
        ] = msg.sender;
        uint8 submissionCount = _getSubmissionCount(nodeSubmissionKey, submissionCountKey);

        // Emit missed attestation penalty submitted event
        emit MissedAttestationPenaltySubmitted(
            msg.sender,
            _missedAttestationPenaltyData.index,
            _missedAttestationPenaltyData.pageNumber,
            block.number
        );

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            uint16 keyCount = _missedAttestationPenaltyData.keyCount;
            for (uint256 i = 0; i < keyCount; i++) {
                bytes32 pubkeyRoot = getPubkeyRoot(
                    _missedAttestationPenaltyData.pubkeys[i * VALIDATOR_PUBKEY_LENGTH:(i + 1) * VALIDATOR_PUBKEY_LENGTH]
                );
                missedAttestationPenalty[pubkeyRoot]++;
            }
            emit MissedAttestationPenaltyUpdated(_missedAttestationPenaltyData.index, block.number);
        }
    }

    function _getSubmissionCount(bytes32 _nodeSubmissionKey, bytes32 _submissionCountKey)
        internal
        returns (uint8 _submissionCount)
    {
        // Check & update node submission status
        if (nodeSubmissionKeys[_nodeSubmissionKey]) revert DuplicateSubmissionFromNode();
        nodeSubmissionKeys[_nodeSubmissionKey] = true;
        submissionCountKeys[_submissionCountKey]++;
        _submissionCount = submissionCountKeys[_submissionCountKey];
    }

    function getCurrentRewardsIndex() external view returns (uint256) {
        return rewardsData.index + 1; // rewardsData.index is the last updated index
    }

    function getPubkeyRoot(bytes calldata _pubkey) public pure returns (bytes32) {
        if (_pubkey.length != 48) revert InvalidPubkeyLength();

        // Append 16 bytes of zero padding to the pubkey and compute its hash to get the pubkey root.
        return sha256(abi.encodePacked(_pubkey, bytes16(0)));
    }

    modifier trustedNodeOnly() {
        if (!isTrustedNode[msg.sender]) revert NotATrustedNode();
        _;
    }
}
