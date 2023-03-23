// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderOracle.sol';
import './interfaces/ISocializingPool.sol';
import './library/Address.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable {
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
    /// @inheritdoc IStaderOracle
    uint256 public override socializingRewardsIndex;
    /// @inheritdoc IStaderOracle
    mapping(uint256 => bytes32) public override socializingRewardsMerkleRoot;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;

    function initialize() external initializer {
        __AccessControl_init_unchained();

        // TODO: Manoj: how 7200 is 24 hrs??
        balanceUpdateFrequency = 7200; // 24 hours
        isTrustedNode[msg.sender] = true;
        trustedNodesCount = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit TrustedNodeAdded(msg.sender);
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

    function submitSocializingRewardsMerkleRoot(uint256 _index, bytes32 _merkleRoot) external override trustedNodeOnly {
        require(_index > socializingRewardsIndex, 'Merkle root index is not higher than the current one');

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(abi.encodePacked(msg.sender, _merkleRoot));
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_merkleRoot));
        // Check & update node submission status
        require(!nodeSubmissionKeys[nodeSubmissionKey], 'Duplicate submission from node');
        nodeSubmissionKeys[nodeSubmissionKey] = true;
        submissionCountKeys[submissionCountKey]++;
        uint8 submissionCount = submissionCountKeys[submissionCountKey];
        // Emit merkle root submitted event
        emit SocializingRewardsMerkleRootSubmitted(msg.sender, _index, _merkleRoot, block.timestamp);
        if (submissionCount == trustedNodesCount / 2 + 1) {
            // Update merkle root
            socializingRewardsMerkleRoot[_index] = _merkleRoot;
            socializingRewardsIndex = _index;
            emit SocializingRewardsMerkleRootUpdated(_index, _merkleRoot, block.timestamp);
        }
    }

    modifier trustedNodeOnly() {
        require(isTrustedNode[msg.sender], 'Not a trusted node');
        _;
    }
}
