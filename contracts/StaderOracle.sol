// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IPoolUtils.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract StaderOracle is IStaderOracle, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    bool public isERDeviationThresholdCrossed;
    SDPriceData public lastReportedSDPriceData;
    IStaderConfig public override staderConfig;
    ExchangeRate public exchangeRate;
    ValidatorStats public validatorStats;

    uint256 public constant TOTAL_DEVIATION = 10000;
    uint256 public deviationThreshold;
    /// @inheritdoc IStaderOracle
    uint256 public override reportingBlockNumberForWithdrawnValidators;
    /// @inheritdoc IStaderOracle
    uint256 public override trustedNodesCount;
    /// @inheritdoc IStaderOracle
    uint256 public override lastReportedMAPDIndex;

    // indicate the health of protocol on beacon chain
    // enabled by `MANAGER` if heavy slashing on protocol on beacon chain
    bool public override safeMode;

    /// @inheritdoc IStaderOracle
    mapping(address => bool) public override isTrustedNode;
    mapping(bytes32 => bool) private nodeSubmissionKeys;
    mapping(bytes32 => uint8) private submissionCountKeys;
    mapping(bytes32 => uint16) public override missedAttestationPenalty;
    uint256[] private sdPrices;

    bytes32 public constant SD_PRICE_UF = keccak256('SD_PRICE_UF'); // SD Price Update Frequency Key
    bytes32 public constant VALIDATOR_STATS_UF = keccak256('VALIDATOR_STATS_UF'); // Validator Status Update Frequency Key
    bytes32 public constant WITHDRAWN_VALIDATORS_UF = keccak256('WITHDRAWN_VALIDATORS_UF'); // Withdrawn Validator Update Frequency Key
    bytes32 public constant MISSED_ATTESTATION_PENALTY_UF = keccak256('MISSED_ATTESTATION_PENALTY_UF'); // Missed Attestation Penalty Update Frequency Key
    mapping(bytes32 => uint256) public updateFrequencyMap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) public initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        deviationThreshold = 500; //5% deviation threshold
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /// @inheritdoc IStaderOracle
    function addTrustedNode(address _nodeAddress) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        UtilLib.checkNonZeroAddress(_nodeAddress);
        if (isTrustedNode[_nodeAddress]) {
            revert NodeAlreadyTrusted();
        }
        isTrustedNode[_nodeAddress] = true;
        trustedNodesCount++;

        emit TrustedNodeAdded(_nodeAddress);
    }

    /// @inheritdoc IStaderOracle
    function removeTrustedNode(address _nodeAddress) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        UtilLib.checkNonZeroAddress(_nodeAddress);
        if (!isTrustedNode[_nodeAddress]) {
            revert NodeNotTrusted();
        }
        isTrustedNode[_nodeAddress] = false;
        trustedNodesCount--;

        emit TrustedNodeRemoved(_nodeAddress);
    }

    /// @inheritdoc IStaderOracle
    function updateExchangeRate() external override whenNotPaused {
        if (isERDeviationThresholdCrossed) {
            revert CrossedDeviationThreshold();
        }
        (, int256 totalETHBalanceInInt, , , ) = AggregatorV3Interface(staderConfig.getETHBalancePORFeedProxy())
            .latestRoundData();
        (, int256 totalETHXSupplyInInt, , , ) = AggregatorV3Interface(staderConfig.getETHXSupplyPORFeedProxy())
            .latestRoundData();
        uint256 totalETHBalance = uint256(totalETHBalanceInInt);
        uint256 totalETHXSupply = uint256(totalETHXSupplyInInt);
        uint256 currentExchange = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();
        uint256 DECIMALS = staderConfig.getDecimals();
        uint256 newExchangeRate = (totalETHBalance == 0 || totalETHXSupply == 0)
            ? DECIMALS
            : (totalETHBalance * DECIMALS) / totalETHXSupply;
        if (
            newExchangeRate < (currentExchange * (TOTAL_DEVIATION - deviationThreshold)) / TOTAL_DEVIATION ||
            newExchangeRate > ((currentExchange * (TOTAL_DEVIATION - deviationThreshold)) / TOTAL_DEVIATION)
        ) {
            isERDeviationThresholdCrossed = true;
            return;
        }
        exchangeRate.totalETHBalance = totalETHBalance;
        exchangeRate.totalETHXSupply = totalETHXSupply;
        exchangeRate.reportingBlockNumber = block.number;

        // Emit balances updated event
        emit ExchangeRateUpdated(
            exchangeRate.reportingBlockNumber,
            exchangeRate.totalETHBalance,
            exchangeRate.totalETHXSupply
        );
    }

    /**
     * @notice update the exchange rate when deviation threshold crossed, after figuring out the reason for deviation
     * @dev `isERDeviationThresholdCrossed` must be true to call this function and only MANAGER is allowed
     */
    function updateExchangeRateWhenDeviationThresholdCrossed() external override whenNotPaused {
        if (!isERDeviationThresholdCrossed) {
            revert DeviationThresholdNotCrossed();
        }
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        isERDeviationThresholdCrossed = false;
        (, int256 totalETHBalanceInInt, , , ) = AggregatorV3Interface(staderConfig.getETHBalancePORFeedProxy())
            .latestRoundData();
        (, int256 totalETHXSupplyInInt, , , ) = AggregatorV3Interface(staderConfig.getETHXSupplyPORFeedProxy())
            .latestRoundData();
        uint256 totalETHBalance = uint256(totalETHBalanceInInt);
        uint256 totalETHXSupply = uint256(totalETHXSupplyInInt);
        exchangeRate.totalETHBalance = totalETHBalance;
        exchangeRate.totalETHXSupply = totalETHXSupply;
        exchangeRate.reportingBlockNumber = block.number;

        // Emit balances updated event
        emit ExchangeRateUpdatedViaManager(
            exchangeRate.reportingBlockNumber,
            exchangeRate.totalETHBalance,
            exchangeRate.totalETHXSupply
        );
    }

    /// @notice submits merkle root and handles reward
    /// sends user rewards to Stader Stake Pool Manager
    /// sends protocol rewards to stader treasury
    /// updates operator reward balances on socializing pool
    /// @param _rewardsData contains rewards merkleRoot and rewards split info
    /// @dev _rewardsData.index should not be zero
    function submitSocializingRewardsMerkleRoot(RewardsData calldata _rewardsData)
        external
        override
        trustedNodeOnly
        whenNotPaused
        nonReentrant
    {
        if (_rewardsData.reportingBlockNumber >= block.number) {
            revert ReportingFutureBlockData();
        }
        if (_rewardsData.reportingBlockNumber != getMerkleRootReportableBlockByPoolId(_rewardsData.poolId)) {
            revert InvalidReportingBlock();
        }
        if (_rewardsData.index != getCurrentRewardsIndexByPoolId(_rewardsData.poolId)) {
            revert InvalidMerkleRootIndex();
        }

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _rewardsData.index,
                _rewardsData.merkleRoot,
                _rewardsData.poolId,
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
                _rewardsData.poolId,
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
            _rewardsData.poolId,
            block.number
        );

        uint8 submissionCount = attestSubmission(nodeSubmissionKey, submissionCountKey);

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            address socializingPool = IPoolUtils(staderConfig.getPoolUtils()).getSocializingPoolAddress(
                _rewardsData.poolId
            );
            ISocializingPool(socializingPool).handleRewards(_rewardsData);

            emit SocializingRewardsMerkleRootUpdated(
                _rewardsData.index,
                _rewardsData.merkleRoot,
                _rewardsData.poolId,
                block.number
            );
        }
    }

    function submitSDPrice(SDPriceData calldata _sdPriceData) external override trustedNodeOnly {
        if (_sdPriceData.reportingBlockNumber >= block.number) {
            revert ReportingFutureBlockData();
        }
        if (_sdPriceData.reportingBlockNumber % updateFrequencyMap[SD_PRICE_UF] > 0) {
            revert InvalidReportingBlock();
        }
        if (_sdPriceData.reportingBlockNumber <= lastReportedSDPriceData.reportingBlockNumber) {
            revert ReportingPreviousCycleData();
        }

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(abi.encodePacked(msg.sender, _sdPriceData.reportingBlockNumber));
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_sdPriceData.reportingBlockNumber));
        uint8 submissionCount = attestSubmission(nodeSubmissionKey, submissionCountKey);
        insertSDPrice(_sdPriceData.sdPriceInETH);
        // Emit SD Price submitted event
        emit SDPriceSubmitted(msg.sender, _sdPriceData.sdPriceInETH, _sdPriceData.reportingBlockNumber, block.number);

        // price can be derived once more than 66% percent oracles have submitted price
        if ((submissionCount == (2 * trustedNodesCount) / 3 + 1)) {
            lastReportedSDPriceData = _sdPriceData;
            lastReportedSDPriceData.sdPriceInETH = getMedianValue(sdPrices);
            uint256 len = sdPrices.length;
            while (len > 0) {
                sdPrices.pop();
                len--;
            }

            // Emit SD Price updated event
            emit SDPriceUpdated(_sdPriceData.sdPriceInETH, _sdPriceData.reportingBlockNumber, block.number);
        }
    }

    function insertSDPrice(uint256 _sdPrice) internal {
        sdPrices.push(_sdPrice);
        if (sdPrices.length == 1) return;

        uint256 j = sdPrices.length - 1;
        while ((j >= 1) && (_sdPrice < sdPrices[j - 1])) {
            sdPrices[j] = sdPrices[j - 1];
            j--;
        }
        sdPrices[j] = _sdPrice;
    }

    function getMedianValue(uint256[] storage dataArray) internal view returns (uint256 _medianValue) {
        uint256 len = dataArray.length;
        return (dataArray[(len - 1) / 2] + dataArray[len / 2]) / 2;
    }

    /// @inheritdoc IStaderOracle
    function submitValidatorStats(ValidatorStats calldata _validatorStats)
        external
        override
        trustedNodeOnly
        whenNotPaused
    {
        if (_validatorStats.reportingBlockNumber >= block.number) {
            revert ReportingFutureBlockData();
        }
        if (_validatorStats.reportingBlockNumber % updateFrequencyMap[VALIDATOR_STATS_UF] > 0) {
            revert InvalidReportingBlock();
        }

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _validatorStats.reportingBlockNumber,
                _validatorStats.exitingValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.exitingValidatorsCount,
                _validatorStats.exitedValidatorsCount,
                _validatorStats.slashedValidatorsCount
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _validatorStats.reportingBlockNumber,
                _validatorStats.exitingValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.exitingValidatorsCount,
                _validatorStats.exitedValidatorsCount,
                _validatorStats.slashedValidatorsCount
            )
        );

        uint8 submissionCount = attestSubmission(nodeSubmissionKey, submissionCountKey);
        // Emit validator stats submitted event
        emit ValidatorStatsSubmitted(
            msg.sender,
            _validatorStats.reportingBlockNumber,
            _validatorStats.exitingValidatorsBalance,
            _validatorStats.exitedValidatorsBalance,
            _validatorStats.slashedValidatorsBalance,
            _validatorStats.exitingValidatorsCount,
            _validatorStats.exitedValidatorsCount,
            _validatorStats.slashedValidatorsCount,
            block.timestamp
        );

        if (
            submissionCount == trustedNodesCount / 2 + 1 &&
            _validatorStats.reportingBlockNumber > validatorStats.reportingBlockNumber
        ) {
            validatorStats = _validatorStats;

            // Emit stats updated event
            emit ValidatorStatsUpdated(
                _validatorStats.reportingBlockNumber,
                _validatorStats.exitingValidatorsBalance,
                _validatorStats.exitedValidatorsBalance,
                _validatorStats.slashedValidatorsBalance,
                _validatorStats.exitingValidatorsCount,
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
        whenNotPaused
        nonReentrant
    {
        if (_withdrawnValidators.reportingBlockNumber >= block.number) {
            revert ReportingFutureBlockData();
        }
        if (_withdrawnValidators.reportingBlockNumber % updateFrequencyMap[WITHDRAWN_VALIDATORS_UF] > 0) {
            revert InvalidReportingBlock();
        }

        bytes memory encodedPubkeys = abi.encode(_withdrawnValidators.sortedPubkeys);
        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(
            abi.encodePacked(
                msg.sender,
                _withdrawnValidators.reportingBlockNumber,
                _withdrawnValidators.nodeRegistry,
                encodedPubkeys
            )
        );
        bytes32 submissionCountKey = keccak256(
            abi.encodePacked(
                _withdrawnValidators.reportingBlockNumber,
                _withdrawnValidators.nodeRegistry,
                encodedPubkeys
            )
        );

        uint8 submissionCount = attestSubmission(nodeSubmissionKey, submissionCountKey);
        // Emit withdrawn validators submitted event
        emit WithdrawnValidatorsSubmitted(
            msg.sender,
            _withdrawnValidators.reportingBlockNumber,
            _withdrawnValidators.nodeRegistry,
            _withdrawnValidators.sortedPubkeys,
            block.timestamp
        );

        if (
            submissionCount == trustedNodesCount / 2 + 1 &&
            _withdrawnValidators.reportingBlockNumber > reportingBlockNumberForWithdrawnValidators
        ) {
            reportingBlockNumberForWithdrawnValidators = _withdrawnValidators.reportingBlockNumber;
            INodeRegistry(_withdrawnValidators.nodeRegistry).withdrawnValidators(_withdrawnValidators.sortedPubkeys);

            // Emit withdrawn validators updated event
            emit WithdrawnValidatorsUpdated(
                _withdrawnValidators.reportingBlockNumber,
                _withdrawnValidators.nodeRegistry,
                _withdrawnValidators.sortedPubkeys,
                block.timestamp
            );
        }
    }

    /// @inheritdoc IStaderOracle
    function submitMissedAttestationPenalties(MissedAttestationPenaltyData calldata _mapd)
        external
        override
        trustedNodeOnly
        whenNotPaused
    {
        if (_mapd.reportingBlockNumber >= block.number) {
            revert ReportingFutureBlockData();
        }
        if (_mapd.reportingBlockNumber != getMissedAttestationPenaltyReportableBlock()) {
            revert InvalidReportingBlock();
        }
        if (_mapd.index != lastReportedMAPDIndex + 1) {
            revert InvalidMAPDIndex();
        }

        bytes memory encodedPubkeys = abi.encode(_mapd.sortedPubkeys);

        // Get submission keys
        bytes32 nodeSubmissionKey = keccak256(abi.encodePacked(msg.sender, _mapd.index, encodedPubkeys));
        bytes32 submissionCountKey = keccak256(abi.encodePacked(_mapd.index, encodedPubkeys));
        uint8 submissionCount = attestSubmission(nodeSubmissionKey, submissionCountKey);

        // Emit missed attestation penalty submitted event
        emit MissedAttestationPenaltySubmitted(
            msg.sender,
            _mapd.index,
            block.number,
            _mapd.reportingBlockNumber,
            _mapd.sortedPubkeys
        );

        if ((submissionCount == trustedNodesCount / 2 + 1)) {
            lastReportedMAPDIndex = _mapd.index;
            uint256 keyCount = _mapd.sortedPubkeys.length;
            for (uint256 i = 0; i < keyCount; i++) {
                bytes32 pubkeyRoot = UtilLib.getPubkeyRoot(_mapd.sortedPubkeys[i]);
                missedAttestationPenalty[pubkeyRoot]++;
            }
            emit MissedAttestationPenaltyUpdated(_mapd.index, block.number, _mapd.sortedPubkeys);
        }
    }

    /// @inheritdoc IStaderOracle
    function enableSafeMode() external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        safeMode = true;
        emit SafeModeEnabled();
    }

    function disableSafeMode() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        safeMode = false;
        emit SafeModeDisabled();
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function setSDPriceUpdateFrequency(uint256 _updateFrequency) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        setUpdateFrequency(SD_PRICE_UF, _updateFrequency);
    }

    function setValidatorStatsUpdateFrequency(uint256 _updateFrequency) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        setUpdateFrequency(VALIDATOR_STATS_UF, _updateFrequency);
    }

    function setWithdrawnValidatorsUpdateFrequency(uint256 _updateFrequency) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        setUpdateFrequency(WITHDRAWN_VALIDATORS_UF, _updateFrequency);
    }

    function setMissedAttestationPenaltyUpdateFrequency(uint256 _updateFrequency) external override {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        setUpdateFrequency(MISSED_ATTESTATION_PENALTY_UF, _updateFrequency);
    }

    function setUpdateFrequency(bytes32 _key, uint256 _updateFrequency) internal {
        if (_updateFrequency == 0) {
            revert ZeroFrequency();
        }
        if (_updateFrequency == updateFrequencyMap[_key]) {
            revert FrequencyUnchanged();
        }
        updateFrequencyMap[_key] = _updateFrequency;

        emit UpdateFrequencyUpdated(_updateFrequency);
    }

    function getMerkleRootReportableBlockByPoolId(uint8 _poolId) public view override returns (uint256) {
        (, , uint256 currentEndBlock) = ISocializingPool(
            IPoolUtils(staderConfig.getPoolUtils()).getSocializingPoolAddress(_poolId)
        ).getRewardDetails();
        return currentEndBlock;
    }

    function getSDPriceReportableBlock() public view override returns (uint256) {
        return getReportableBlockFor(SD_PRICE_UF);
    }

    function getValidatorStatsReportableBlock() public view override returns (uint256) {
        return getReportableBlockFor(VALIDATOR_STATS_UF);
    }

    function getWithdrawnValidatorReportableBlock() public view override returns (uint256) {
        return getReportableBlockFor(WITHDRAWN_VALIDATORS_UF);
    }

    function getMissedAttestationPenaltyReportableBlock() public view override returns (uint256) {
        return getReportableBlockFor(MISSED_ATTESTATION_PENALTY_UF);
    }

    function getReportableBlockFor(bytes32 _key) internal view returns (uint256) {
        uint256 updateFrequency = updateFrequencyMap[_key];
        if (updateFrequency == 0) {
            revert UpdateFrequencyNotSet();
        }
        return (block.number / updateFrequency) * updateFrequency;
    }

    function getCurrentRewardsIndexByPoolId(uint8 _poolId) public view returns (uint256) {
        return
            ISocializingPool(IPoolUtils(staderConfig.getPoolUtils()).getSocializingPoolAddress(_poolId))
                .getCurrentRewardsIndex();
    }

    function getValidatorStats() external view override returns (ValidatorStats memory) {
        return (validatorStats);
    }

    function getExchangeRate() external view override returns (ExchangeRate memory) {
        return (exchangeRate);
    }

    function attestSubmission(bytes32 _nodeSubmissionKey, bytes32 _submissionCountKey)
        internal
        returns (uint8 _submissionCount)
    {
        // Check & update node submission status
        if (nodeSubmissionKeys[_nodeSubmissionKey]) {
            revert DuplicateSubmissionFromNode();
        }
        nodeSubmissionKeys[_nodeSubmissionKey] = true;
        submissionCountKeys[_submissionCountKey]++;
        _submissionCount = submissionCountKeys[_submissionCountKey];
    }

    function getSDPriceInETH() external view override returns (uint256) {
        return lastReportedSDPriceData.sdPriceInETH;
    }

    modifier trustedNodeOnly() {
        if (!isTrustedNode[msg.sender]) {
            revert NotATrustedNode();
        }
        _;
    }
}
