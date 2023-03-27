// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderOracle.sol';
import './interfaces/INodeRegistry.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable {
    ExchangeRate public exchangeRate;
    ValidatorStats public validatorStats;
    /// @inheritdoc IStaderOracle
    uint256 public override updateFrequency;
    uint256 public override lastUpdatedBlockNumberForWithdrawnValidators;
    /// @inheritdoc IStaderOracle
    uint256 public override trustedNodesCount;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;

    address public nodeRegistry;

    function initialize(address _nodeRegistry) external initializer {
        require(_nodeRegistry != address(0), 'nodeRegistry is zero');

        __AccessControl_init_unchained();

        updateFrequency = 7200; // 24 hours
        isTrustedNode[msg.sender] = true;
        trustedNodesCount = 1;
        nodeRegistry = _nodeRegistry;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit TrustedNodeAdded(msg.sender);
    }

    /// @inheritdoc IStaderOracle
    function addTrustedNode(address _nodeAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nodeAddress != address(0), 'nodeAddress is zero');
        require(!isTrustedNode[_nodeAddress], 'Node is already trusted');
        isTrustedNode[_nodeAddress] = true;
        trustedNodesCount++;

        emit TrustedNodeAdded(_nodeAddress);
    }

    /// @inheritdoc IStaderOracle
    function removeTrustedNode(address _nodeAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nodeAddress != address(0), 'nodeAddress is zero');
        require(isTrustedNode[_nodeAddress], 'Node is not trusted');
        isTrustedNode[_nodeAddress] = false;
        trustedNodesCount--;

        emit TrustedNodeRemoved(_nodeAddress);
    }

    function setUpdateFrequency(uint256 _updateFrequency) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_updateFrequency > 0, 'Frequency is zero');
        require(_updateFrequency != updateFrequency, 'Frequency is unchanged');
        updateFrequency = _updateFrequency;

        emit UpdateFrequencyUpdated(_updateFrequency);
    }

    function setNodeRegistry(address _nodeRegistry) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nodeRegistry != address(0), 'nodeRegistry is zero');
        require(_nodeRegistry != nodeRegistry, 'nodeRegistry is unchanged');
        nodeRegistry = _nodeRegistry;
    }

    /// @inheritdoc IStaderOracle
    function submitBalances(ExchangeRate calldata _exchangeRate) external override trustedNodeOnly {
        require(_exchangeRate.lastUpdatedBlockNumber < block.number, 'Data can not be submitted for a future block');
        require(
            _exchangeRate.lastUpdatedBlockNumber > exchangeRate.lastUpdatedBlockNumber,
            'Data for an equal or higher block are set'
        );
        require(_exchangeRate.totalStakingETHBalance <= _exchangeRate.totalETHBalance, 'Invalid network balances');

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
        // Check & update node submission status
        require(!nodeSubmissionKeys[nodeSubmissionKey], 'Duplicate submission from node');
        nodeSubmissionKeys[nodeSubmissionKey] = true;
        submissionCountKeys[submissionCountKey]++;
        uint8 submissionCount = submissionCountKeys[submissionCountKey];
        // Emit balances submitted event
        emit BalancesSubmitted(
            msg.sender,
            _exchangeRate.lastUpdatedBlockNumber,
            _exchangeRate.totalETHBalance,
            _exchangeRate.totalStakingETHBalance,
            _exchangeRate.totalETHXSupply,
            block.timestamp
        );

        if (submissionCount >= trustedNodesCount / 2 + 1) {
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

    /// @inheritdoc IStaderOracle
    function submitValidatorStats(ValidatorStats calldata _validatorStats) external override trustedNodeOnly {
        require(_validatorStats.lastUpdatedBlockNumber < block.number, 'Data can not be submitted for a future block');
        require(
            _validatorStats.lastUpdatedBlockNumber > validatorStats.lastUpdatedBlockNumber,
            'Data for an equal or higher block are set'
        );

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
        // Check & update node submission status
        require(!nodeSubmissionKeys[nodeSubmissionKey], 'Duplicate submission from node');
        nodeSubmissionKeys[nodeSubmissionKey] = true;
        submissionCountKeys[submissionCountKey]++;
        uint8 submissionCount = submissionCountKeys[submissionCountKey];
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

        if (submissionCount >= trustedNodesCount / 2 + 1) {
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
        require(
            _withdrawnValidators.lastUpdatedBlockNumber < block.number,
            'Data can not be submitted for a future block'
        );
        require(
            _withdrawnValidators.lastUpdatedBlockNumber > lastUpdatedBlockNumberForWithdrawnValidators,
            'Data for an equal or higher block are set'
        );

        // Ensure the pubkeys array is sorted
        require(isSorted(_withdrawnValidators.sortedPubkeys), 'Pubkeys must be sorted');

        bytes memory encodedPubkeys = abi.encode(_withdrawnValidators.sortedPubkeys);
        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(msg.sender, _withdrawnValidators.lastUpdatedBlockNumber, encodedPubkeys)
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(_withdrawnValidators.lastUpdatedBlockNumber, encodedPubkeys)
        );

        // Check & update node submission status
        require(!nodeSubmissionKeys[nodeSubmissionKey], 'Duplicate submission from node');
        nodeSubmissionKeys[nodeSubmissionKey] = true;
        submissionCountKeys[submissionCountKey]++;
        uint8 submissionCount = submissionCountKeys[submissionCountKey];

        // Emit withdrawn validators submitted event
        emit WithdrawnValidatorsSubmitted(
            msg.sender,
            _withdrawnValidators.lastUpdatedBlockNumber,
            _withdrawnValidators.sortedPubkeys,
            block.timestamp
        );

        if (submissionCount >= trustedNodesCount / 2 + 1) {
            lastUpdatedBlockNumberForWithdrawnValidators = _withdrawnValidators.lastUpdatedBlockNumber;
            INodeRegistry(nodeRegistry).withdrawnValidators(_withdrawnValidators.sortedPubkeys);

            // Emit withdrawn validators updated event
            emit WithdrawnValidatorsUpdated(
                _withdrawnValidators.lastUpdatedBlockNumber,
                _withdrawnValidators.sortedPubkeys,
                block.timestamp
            );
        }
    }

    function getValidatorStats() external view override returns (ValidatorStats memory) {
        return (validatorStats);
    }

    function getExchangeRate() external view override returns (ExchangeRate memory) {
        return (exchangeRate);
    }

    modifier trustedNodeOnly() {
        require(isTrustedNode[msg.sender], 'Not a trusted node');
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
