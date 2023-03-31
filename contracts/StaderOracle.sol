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

    uint64 private constant PUBKEY_LENGTH = 48;

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

    uint256 public lastMissedAttestationIndex;

    /// @inheritdoc IStaderOracle
    mapping(uint256 => bytes32) public override socializingRewardsMerkleRoot;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;
    mapping(bytes32 => uint16) public override missedAttestationPenalty;
    mapping(address => mapping(uint256 => uint256)) MissedAttestationDataByTrustedNode;

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
        require(!isTrustedNode[_nodeAddress], 'Node is already trusted');
        isTrustedNode[_nodeAddress] = true;
        trustedNodesCount++;

        emit TrustedNodeAdded(_nodeAddress);
    }

    /// @inheritdoc IStaderOracle
    function removeTrustedNode(address _nodeAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_nodeAddress);
        require(isTrustedNode[_nodeAddress], 'Node is not trusted');
        isTrustedNode[_nodeAddress] = false;
        trustedNodesCount--;

        emit TrustedNodeRemoved(_nodeAddress);
    }

    function setUpdateFrequency(uint256 _balanceUpdateFrequency) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_balanceUpdateFrequency > 0, 'Frequency is zero');
        require(_balanceUpdateFrequency != balanceUpdateFrequency, 'Frequency is unchanged');
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
        require(_block < block.number, 'Balances can not be submitted for a future block');
        require(_block > lastBlockNumberBalancesUpdated, 'Network balances for an equal or higher block are set');
        // Check balances
        require(_stakingEth <= _totalEth, 'Invalid network balances');
        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(msg.sender, _block, _totalEth, _stakingEth, _ethxSupply)
        );
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_block, _totalEth, _stakingEth, _ethxSupply));
        // Check & update node submission status
        require(!nodeSubmissionKeys[nodeSubmissionKey], 'Duplicate submission from node');
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
        require(
            _rewardsData.lastUpdatedBlockNumber < block.number,
            'Rewards data can not be submitted for a future block'
        );

        require(_rewardsData.index > rewardsData.index, 'Merkle root index is not higher than the current one');

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
        require(
            _missedAttestationPenaltyData.lastUpdatedBlockNumber < block.number,
            'missed attestation penalty data can not be submitted for a future block'
        );

        //TODO sanjay we will not store the `missedAttestationPenaltyData`
        require(
            _missedAttestationPenaltyData.index >= lastMissedAttestationIndex,
            'missed attestation penalty data index is not higher than the current one'
        );

        require(
            _missedAttestationPenaltyData.keyCount * PUBKEY_LENGTH == _missedAttestationPenaltyData.pubkeys.length,
            'invalid data'
        );

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

        uint8 submissionCount = _getSubmissionCount(nodeSubmissionKey, submissionCountKey);
        // Emit missed attestation penalty submitted event
        emit MissedAttestationPenaltySubmitted(
            msg.sender,
            _missedAttestationPenaltyData.index,
            _missedAttestationPenaltyData.pageNumber,
            block.number
        );

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            lastMissedAttestationIndex = _missedAttestationPenaltyData.index;
            uint16 keyCount = _missedAttestationPenaltyData.keyCount;
            // missedAttestationPenaltyData = _missedAttestationPenaltyData;
            for (uint256 i = 0; i < keyCount; i++) {
                bytes32 pubkeyRoot = getPubkeyRoot(
                    _missedAttestationPenaltyData.pubkeys[i * PUBKEY_LENGTH:(i + 1) * PUBKEY_LENGTH]
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
        require(!nodeSubmissionKeys[_nodeSubmissionKey], 'Duplicate submission from node');
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
        require(isTrustedNode[msg.sender], 'Not a trusted node');
        _;
    }
}
