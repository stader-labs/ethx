// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/INodeRegistry.sol';
import './library/Address.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable {
    RewardsData public rewardsData;

    uint64 private constant VALIDATOR_PUBKEY_LENGTH = 48;

    IStaderConfig public staderConfig;
    ExchangeRate public exchangeRate;
    ValidatorStats public validatorStats;
    /// @inheritdoc IStaderOracle
    uint256 public override updateFrequency;
    uint256 public override lastUpdatedBlockNumberForWithdrawnValidators;
    /// @inheritdoc IStaderOracle
    uint256 public override trustedNodesCount;
    /// @inheritdoc IStaderOracle
    uint256 public override latestMissedAttestationConsensusIndex;

    /// @inheritdoc IStaderOracle
    mapping(uint256 => bytes32) public override socializingRewardsMerkleRoot;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;
    mapping(bytes32 => uint16) public override missedAttestationPenalty;
    // mapping of trusted node address with report index and report pageNumber
    mapping(address => MissedAttestationReportInfo) public missedAttestationDataByTrustedNode;

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();

        updateFrequency = 7200; // 24 hours

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

    function setUpdateFrequency(uint256 _updateFrequency) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_updateFrequency == 0) revert ZeroFrequency();
        if (_updateFrequency == updateFrequency) revert FrequencyUnchanged();
        updateFrequency = _updateFrequency;

        emit UpdateFrequencyUpdated(_updateFrequency);
    }

    /// @inheritdoc IStaderOracle
    function submitBalances(ExchangeRate calldata _exchangeRate) external override trustedNodeOnly {
        if (_exchangeRate.lastUpdatedBlockNumber >= block.number) revert ReportingFutureBlockData();
        if (_exchangeRate.totalStakingETHBalance > _exchangeRate.totalETHBalance) revert InvalidNetworkBalances();

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _exchangeRate.lastUpdatedBlockNumber,
                _exchangeRate.totalETHBalance,
                _exchangeRate.totalStakingETHBalance,
                _exchangeRate.totalETHXSupply
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _exchangeRate.lastUpdatedBlockNumber,
                _exchangeRate.totalETHBalance,
                _exchangeRate.totalStakingETHBalance,
                _exchangeRate.totalETHXSupply
            )
        );
        uint8 submissionCount = _attestSubmission(nodeSubmissionKey, submissionCountKey);
        // Emit balances submitted event
        emit BalancesSubmitted(
            msg.sender,
            _exchangeRate.lastUpdatedBlockNumber,
            _exchangeRate.totalETHBalance,
            _exchangeRate.totalStakingETHBalance,
            _exchangeRate.totalETHXSupply,
            block.timestamp
        );

        if (
            submissionCount >= trustedNodesCount / 2 + 1 &&
            _exchangeRate.lastUpdatedBlockNumber > exchangeRate.lastUpdatedBlockNumber
        ) {
            exchangeRate = _exchangeRate;

            // Emit balances updated event
            emit BalancesUpdated(
                _exchangeRate.lastUpdatedBlockNumber,
                _exchangeRate.totalETHBalance,
                _exchangeRate.totalStakingETHBalance,
                _exchangeRate.totalETHXSupply,
                block.timestamp
            );
        }
    }

    // Returns the latest block number that oracles should be reporting balances for
    function getLatestReportableBlock() external view override returns (uint256) {
        // Calculate the last reportable block based on update frequency
        return (block.number / updateFrequency) * updateFrequency;
    }

    /// @notice submits merkle root and handles reward
    /// sends user rewards to Stader Stake Pool Manager
    /// sends protocol rewards to stader treasury
    /// updates operator reward balances on socializing pool
    /// @param _rewardsData contains rewards merkleRoot and rewards split info
    /// @dev _rewardsData.index should not be zero
    function submitSocializingRewardsMerkleRoot(RewardsData calldata _rewardsData) external override trustedNodeOnly {
        if (_rewardsData.lastUpdatedBlockNumber >= block.number) revert ReportingFutureBlockData();

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

        // Emit merkle root submitted event
        emit SocializingRewardsMerkleRootSubmitted(
            msg.sender,
            _rewardsData.index,
            _rewardsData.merkleRoot,
            block.number
        );

        uint8 submissionCount = _attestSubmission(nodeSubmissionKey, submissionCountKey);

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

    /// @inheritdoc IStaderOracle
    function submitValidatorStats(ValidatorStats calldata _validatorStats) external override trustedNodeOnly {
        if (_validatorStats.lastUpdatedBlockNumber >= block.number) revert ReportingFutureBlockData();

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _validatorStats.lastUpdatedBlockNumber,
                _validatorStats.activeValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.activeValidatorsCount,
                _validatorStats.exitedValidatorsCount,
                _validatorStats.slashedValidatorsCount
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _validatorStats.lastUpdatedBlockNumber,
                _validatorStats.activeValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.activeValidatorsCount,
                _validatorStats.exitedValidatorsCount,
                _validatorStats.slashedValidatorsCount
            )
        );

        uint8 submissionCount = _attestSubmission(nodeSubmissionKey, submissionCountKey);
        // Emit validator stats submitted event
        emit ValidatorStatsSubmitted(
            msg.sender,
            _validatorStats.lastUpdatedBlockNumber,
            _validatorStats.activeValidatorsBalance,
            _validatorStats.exitedValidatorsBalance,
            _validatorStats.slashedValidatorsBalance,
            _validatorStats.activeValidatorsCount,
            _validatorStats.exitedValidatorsCount,
            _validatorStats.slashedValidatorsCount,
            block.timestamp
        );

        if (
            submissionCount >= trustedNodesCount / 2 + 1 &&
            _validatorStats.lastUpdatedBlockNumber > validatorStats.lastUpdatedBlockNumber
        ) {
            validatorStats = _validatorStats;

            // Emit stats updated event
            emit ValidatorStatsUpdated(
                _validatorStats.lastUpdatedBlockNumber,
                _validatorStats.activeValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.activeValidatorsCount,
                _validatorStats.exitedValidatorsCount,
                _validatorStats.slashedValidatorsCount,
                block.timestamp
            );
        }
    }

    /// @inheritdoc IStaderOracle
    function submitWithdrawnValidators(WithdrawnValidators calldata _withdrawnValidators)
        external
        override
        trustedNodeOnly
    {
        if (_withdrawnValidators.lastUpdatedBlockNumber >= block.number) revert ReportingFutureBlockData();

        // Ensure the pubkeys array is sorted
        if (!isSorted(_withdrawnValidators.sortedPubkeys)) revert PubkeysNotSorted();

        bytes memory encodedPubkeys = abi.encode(_withdrawnValidators.sortedPubkeys);
        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _withdrawnValidators.lastUpdatedBlockNumber,
                _withdrawnValidators.nodeRegistry,
                encodedPubkeys
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _withdrawnValidators.lastUpdatedBlockNumber,
                _withdrawnValidators.nodeRegistry,
                encodedPubkeys
            )
        );

        uint8 submissionCount = _attestSubmission(nodeSubmissionKey, submissionCountKey);
        // Emit withdrawn validators submitted event
        emit WithdrawnValidatorsSubmitted(
            msg.sender,
            _withdrawnValidators.lastUpdatedBlockNumber,
            _withdrawnValidators.nodeRegistry,
            _withdrawnValidators.sortedPubkeys,
            block.timestamp
        );

        if (
            submissionCount >= trustedNodesCount / 2 + 1 &&
            _withdrawnValidators.lastUpdatedBlockNumber > lastUpdatedBlockNumberForWithdrawnValidators
        ) {
            lastUpdatedBlockNumberForWithdrawnValidators = _withdrawnValidators.lastUpdatedBlockNumber;
            INodeRegistry(_withdrawnValidators.nodeRegistry).withdrawnValidators(_withdrawnValidators.sortedPubkeys);

            // Emit withdrawn validators updated event
            emit WithdrawnValidatorsUpdated(
                _withdrawnValidators.lastUpdatedBlockNumber,
                _withdrawnValidators.nodeRegistry,
                _withdrawnValidators.sortedPubkeys,
                block.timestamp
            );
        }
    }

    /**
     * @notice store the missed attestation penalty strike on validator
     * @dev _missedAttestationPenaltyData.index should not be zero
     * @param _mapd missed attestation penalty data
     */
    function submitMissedAttestationPenalties(MissedAttestationPenaltyData calldata _mapd) external trustedNodeOnly {
        if (_mapd.reportingBlockNumber >= block.number) revert ReportingFutureBlockData();
        if (_mapd.index <= latestMissedAttestationConsensusIndex) revert StaleData();

        MissedAttestationReportInfo memory reportInfo = missedAttestationDataByTrustedNode[msg.sender];
        if (_mapd.index < reportInfo.index) revert ReportingPreviousCycleData();
        if (_mapd.pageNumber <= reportInfo.pageNumber) revert PageNumberAlreadyReported();
        if (_mapd.keyCount * VALIDATOR_PUBKEY_LENGTH != _mapd.pubkeys.length) revert InvalidData();

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(msg.sender, _mapd.index, _mapd.pageNumber, _mapd.pubkeys)
        );
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_mapd.index, _mapd.pageNumber, _mapd.pubkeys));

        missedAttestationDataByTrustedNode[msg.sender] = MissedAttestationReportInfo(_mapd.index, _mapd.pageNumber);
        uint8 submissionCount = _attestSubmission(nodeSubmissionKey, submissionCountKey);

        // Emit missed attestation penalty submitted event
        emit MissedAttestationPenaltySubmitted(
            msg.sender,
            _mapd.index,
            _mapd.pageNumber,
            block.number,
            _mapd.reportingBlockNumber
        );

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            latestMissedAttestationConsensusIndex = _mapd.index;
            uint16 keyCount = _mapd.keyCount;
            for (uint256 i = 0; i < keyCount; i++) {
                bytes32 pubkeyRoot = getPubkeyRoot(
                    _mapd.pubkeys[i * VALIDATOR_PUBKEY_LENGTH:(i + 1) * VALIDATOR_PUBKEY_LENGTH]
                );
                missedAttestationPenalty[pubkeyRoot]++;
            }
            emit MissedAttestationPenaltyUpdated(_mapd.index, block.number);
        }
    }

    function _attestSubmission(bytes32 _nodeSubmissionKey, bytes32 _submissionCountKey)
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

    function getValidatorStats() external view override returns (ValidatorStats memory) {
        return (validatorStats);
    }

    function getExchangeRate() external view override returns (ExchangeRate memory) {
        return (exchangeRate);
    }

    modifier trustedNodeOnly() {
        if (!isTrustedNode[msg.sender]) revert NotATrustedNode();
        _;
    }

    /// @notice Check if the array of pubkeys is sorted.
    /// @param pubkeys The array of pubkeys to check.
    /// @return True if the array is sorted, false otherwise.
    function isSorted(bytes[] memory pubkeys) internal pure returns (bool) {
        for (uint256 i = 0; i < pubkeys.length - 1; i++) {
            if (keccak256(pubkeys[i]) > keccak256(pubkeys[i + 1])) {
                return false;
            }
        }
        return true;
    }
}
