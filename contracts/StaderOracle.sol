// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderOracle.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable {
    /// @inheritdoc IStaderOracle
    ExchangeRate public exchangeRate;
    /// @inheritdoc IStaderOracle
    ValidatorStats public validatorStats;
    /// @inheritdoc IStaderOracle
    uint256 public override updateFrequency;
    /// @inheritdoc IStaderOracle
    uint256 public override trustedNodesCount;
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;

    function initialize() external initializer {
        __AccessControl_init_unchained();

        updateFrequency = 7200; // 24 hours
        isTrustedNode[msg.sender] = true;
        trustedNodesCount = 1;

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

    /// @inheritdoc IStaderOracle
    function submitBalances(
        uint256 _block,
        uint256 _totalEth,
        uint256 _stakingEth,
        uint256 _ethxSupply
    ) external override trustedNodeOnly {
        require(_block < block.number, 'Balances can not be submitted for a future block');
        require(_block > exchangeRate.lastUpdatedBlockNumber, 'Network balances for an equal or higher block are set');
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

        if (submissionCount >= trustedNodesCount / 2 + 1 && _block > exchangeRate.lastUpdatedBlockNumber) {
            // Update balances
            exchangeRate.lastUpdatedBlockNumber = _block;
            exchangeRate.totalETHBalance = _totalEth;
            exchangeRate.totalStakingETHBalance = _stakingEth;
            exchangeRate.totalETHXSupply = _ethxSupply;

            // Emit balances updated event
            emit BalancesUpdated(_block, _totalEth, _stakingEth, _ethxSupply, block.timestamp);
        }
    }

    // Returns the latest block number that oracles should be reporting balances for
    function getLatestReportableBlock() external view override returns (uint256) {
        // Calculate the last reportable block based on update frequency
        return (block.number / updateFrequency) * updateFrequency;
    }

    /// @inheritdoc IStaderOracle
    function submitValidatorStats(
        uint256 _blockNumber,
        uint128 _activeValidatorsBalance,
        uint128 _exitedValidatorsBalance,
        uint128 _slashedValidatorsBalance,
        uint32 _activeValidatorsCount,
        uint32 _exitedValidatorsCount,
        uint32 _slashedValidatorsCount
    ) external override trustedNodeOnly {
        require(_blockNumber < block.number, 'Balances can not be submitted for a future block');
        require(
            _blockNumber > validatorStats.lastUpdatedBlockNumber,
            'Network balances for an equal or higher block are set'
        );

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _blockNumber,
                _activeValidatorsBalance,
                _exitedValidatorsBalance,
                _slashedValidatorsBalance,
                _activeValidatorsCount,
                _exitedValidatorsCount,
                _slashedValidatorsCount
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _blockNumber,
                _activeValidatorsBalance,
                _exitedValidatorsBalance,
                _slashedValidatorsBalance,
                _activeValidatorsCount,
                _exitedValidatorsCount,
                _slashedValidatorsCount
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
            _blockNumber,
            _activeValidatorsBalance,
            _exitedValidatorsBalance,
            _slashedValidatorsBalance,
            _activeValidatorsCount,
            _exitedValidatorsCount,
            _slashedValidatorsCount,
            block.timestamp
        );

        if (submissionCount >= trustedNodesCount / 2 + 1 && _blockNumber > validatorStats.lastUpdatedBlockNumber) {
            // Update stats
            validatorStats.lastUpdatedBlockNumber = _blockNumber;
            validatorStats.activeValidatorsBalance = _activeValidatorsBalance;
            validatorStats.exitedValidatorsBalance = _exitedValidatorsBalance;
            validatorStats.slashedValidatorsBalance = _slashedValidatorsBalance;
            validatorStats.activeValidatorsCount = _activeValidatorsCount;
            validatorStats.exitedValidatorsCount = _exitedValidatorsCount;
            validatorStats.slashedValidatorsCount = _slashedValidatorsCount;

            // Emit stats updated event
            emit ValidatorStatsUpdated(
                _blockNumber,
                _activeValidatorsBalance,
                _exitedValidatorsBalance,
                _slashedValidatorsBalance,
                _activeValidatorsCount,
                _exitedValidatorsCount,
                _slashedValidatorsCount,
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
}
