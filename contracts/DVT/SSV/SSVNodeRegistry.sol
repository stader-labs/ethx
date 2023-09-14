// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../library/UtilLib.sol';
import '../../library/ValidatorStatus.sol';

import '../../interfaces/IPoolUtils.sol';
import '../../interfaces/INodeRegistry.sol';
import '../../interfaces/IStaderConfig.sol';
import '../../interfaces/IVaultFactory.sol';

import '../../interfaces/DVT/SSV/ISSVPool.sol';
import '../../interfaces/IStaderInsuranceFund.sol';
import '../../interfaces/SSVNetwork/ISSVNetwork.sol';
import '../../interfaces/DVT/SSV/ISSVNodeRegistry.sol';
import '../../interfaces/IOperatorRewardsCollector.sol';
import '../../interfaces/SDCollateral/ISDCollateral.sol';
import '../../interfaces/SSVNetwork/ISSVNetworkViews.sol';
import '../../interfaces/DVT/SSV/ISSVValidatorWithdrawalVault.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract SSVNodeRegistry is
    ISSVNodeRegistry,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint8 public constant override POOL_ID = 3;
    uint8 public constant override CLUSTER_SIZE = 4;
    uint16 public override inputKeyCountLimit;
    uint64 public batchSizeToRemoveValidatorFromSSV;
    uint64 public batchSizeToRegisterValidatorFromSSV;

    IStaderConfig public staderConfig;
    ISSVNetwork public ssvNetwork;
    ISSVNetworkViews public ssvNetworkViews;

    uint256 public nextOperatorId;
    uint256 public nextValidatorId;
    uint256 public verifiedKeyBatchSize;
    uint256 public nextQueuedValidatorIndex;
    uint256 public totalActiveValidatorCount;
    uint256 public constant COLLATERAL_ETH = 1.6 ether;
    uint256 public constant COLLATERAL_ETH_PER_KEY_SHARE = 0.8 ether;

    // mapping of validator Id and Validator struct
    mapping(uint256 => Validator) public validatorRegistry;
    // mapping of validator public key and validator Id
    mapping(bytes => uint256) public validatorIdByPubkey;
    //mapping of stader operators Ids assigned to a validator
    mapping(bytes => uint256[]) public operatorIdssByPubkey;
    // mapping of operator Id and Operator struct
    mapping(uint256 => SSVOperator) public operatorStructById;
    // mapping of operator address and operator Id
    mapping(address => uint256) public operatorIDByAddress;
    // mapping of whitelisted permissioned node operator
    mapping(address => bool) public permissionList;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _staderConfig,
        address _ssvNetwork,
        address _ssvNetworkViews
    ) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        UtilLib.checkNonZeroAddress(_ssvNetwork);
        UtilLib.checkNonZeroAddress(_ssvNetworkViews);
        __AccessControl_init_unchained();
        __Pausable_init();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        ssvNetwork = ISSVNetwork(_ssvNetwork);
        ssvNetworkViews = ISSVNetworkViews(_ssvNetworkViews);
        nextOperatorId = 1;
        nextValidatorId = 1;
        inputKeyCountLimit = 30;
        verifiedKeyBatchSize = 50;
        batchSizeToRemoveValidatorFromSSV = 10;
        batchSizeToRegisterValidatorFromSSV = 10;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice white list the permissioned node operator
     * @dev only `MANAGER` can call, whitelisting a one way change there is no blacklisting
     * @param _permissionedNOs array of permissioned NOs address
     */
    function whitelistPermissionedNOs(address[] calldata _permissionedNOs) external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        uint256 permissionedNosLength = _permissionedNOs.length;
        for (uint256 i; i < permissionedNosLength; i++) {
            address operator = _permissionedNOs[i];
            UtilLib.checkNonZeroAddress(operator);
            permissionList[operator] = true;
            emit OperatorWhitelisted(operator);
        }
    }

    /**
     * @notice onboard a node operator
     * @param _ssvOperatorID SSV defined ID of the operator
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     */
    function onboardNodeOperator(
        uint64 _ssvOperatorID,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external whenNotPaused {
        address poolUtils = staderConfig.getPoolUtils();
        if (IPoolUtils(poolUtils).poolAddressById(POOL_ID) != staderConfig.getSSVPool()) {
            revert DuplicatePoolIDOrPoolNotAdded();
        }
        IPoolUtils(poolUtils).onlyValidName(_operatorName);
        UtilLib.checkNonZeroAddress(_operatorRewardAddress);
        // verify weather operator is onboard with SSV along with being a private and active
        // checks if operator has whitelisted this contract address
        (address operatorOwner, , , address whitelisted, bool isPrivate, bool isActive) = ssvNetworkViews
            .getOperatorById(_ssvOperatorID);
        if (msg.sender != operatorOwner || whitelisted != address(this) || isPrivate != true || isActive != true) {
            revert CallerFailingSSVOperatorChecks();
        }
        //checks if operator already onboarded in any pool of protocol
        if (IPoolUtils(poolUtils).isExistingOperator(msg.sender)) {
            revert OperatorAlreadyOnBoardedInProtocol();
        }
        operatorStructById[nextOperatorId] = SSVOperator(
            permissionList[msg.sender],
            _operatorName,
            _operatorRewardAddress,
            msg.sender,
            _ssvOperatorID,
            0,
            0
        );
        operatorIDByAddress[msg.sender] = nextOperatorId;
        nextOperatorId++;
        emit SSVOperatorOnboard(msg.sender, nextOperatorId - 1);
    }

    /**
     * @notice permissionless NO deposit collateral amount to run validators
     * @dev allows only permissionless operator to add collateral
     * amount of collateral should be multiple of collateral required per key-share
     */
    function depositCollateral() external payable {
        uint256 operatorId = operatorIDByAddress[msg.sender];
        _verifyOperatorAndDepositAmount(operatorId, msg.value);
        operatorStructById[operatorId].bondAmount += msg.value;
        emit BondDeposited(msg.sender, msg.value);
    }

    /**
     * @notice add validator keys
     * @dev only accepts call from stader `OPERATOR`
     * @param _pubkey pubkey key of validators
     * @param _preDepositSignature signature of a validators for 1ETH deposit
     * @param _depositSignature signature of a validator for 31ETH deposit
     */
    function addValidatorKeys(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        bytes[] calldata _depositSignature
    ) external whenNotPaused {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        uint256 keyCount = _pubkey.length;
        _verifyAddValidatorsKeysInputParams(keyCount, _preDepositSignature.length, _depositSignature.length);
        address vaultFactory = staderConfig.getVaultFactory();
        address poolUtils = staderConfig.getPoolUtils();
        for (uint256 i; i < keyCount; ) {
            IPoolUtils(poolUtils).onlyValidKeys(_pubkey[i], _preDepositSignature[i], _depositSignature[i]);
            address withdrawVault = IVaultFactory(vaultFactory).deploySSVValidatorWithdrawalVault(
                POOL_ID,
                nextValidatorId
            );
            validatorRegistry[nextValidatorId] = Validator(
                ValidatorStatus.INITIALIZED,
                _pubkey[i],
                _preDepositSignature[i],
                _depositSignature[i],
                withdrawVault,
                0,
                0,
                0
            );
            validatorIdByPubkey[_pubkey[i]] = nextValidatorId;
            emit AddedValidatorKey(msg.sender, _pubkey[i], nextValidatorId);
            nextValidatorId++;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice move validator state from PRE_DEPOSIT to DEPOSIT
     * after verifying pre-sign message, front running and deposit signature.
     * report front run and invalid signature pubkeys
     * @dev only stader oracle contract can call
     * @param _readyToDepositPubkey array of pubkeys ready to be moved to DEPOSIT state
     * @param _frontRunPubkey array for pubkeys which got front deposit
     * @param _invalidSignaturePubkey array of pubkey which has invalid signature for deposit
     */
    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external nonReentrant whenNotPaused {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STADER_ORACLE());
        uint256 readyToDepositValidatorsLength = _readyToDepositPubkey.length;
        uint256 frontRunValidatorsLength = _frontRunPubkey.length;
        uint256 invalidSignatureValidatorsLength = _invalidSignaturePubkey.length;

        if (
            readyToDepositValidatorsLength + frontRunValidatorsLength + invalidSignatureValidatorsLength >
            verifiedKeyBatchSize
        ) {
            revert TooManyVerifiedKeysReported();
        }

        //handle the front run validators
        for (uint256 i; i < frontRunValidatorsLength; ) {
            uint256 validatorId = validatorIdByPubkey[_frontRunPubkey[i]];
            // only PRE_DEPOSIT status check will also include validatorId = 0 check
            // as status for that will be INITIALIZED(default status)
            _onlyPreDepositValidator(validatorId);
            validatorRegistry[validatorId].status = ValidatorStatus.FRONT_RUN;
            emit ValidatorMarkedAsFrontRunned(_frontRunPubkey[i], validatorId);
            unchecked {
                ++i;
            }
        }

        //handle the invalid signature validators
        for (uint256 i; i < invalidSignatureValidatorsLength; ) {
            uint256 validatorId = validatorIdByPubkey[_invalidSignaturePubkey[i]];
            // only PRE_DEPOSIT status check will also include validatorId = 0 check
            // as status for that will be INITIALIZED(default status)
            _onlyPreDepositValidator(validatorId);
            validatorRegistry[validatorId].status = ValidatorStatus.INVALID_SIGNATURE;
            emit ValidatorStatusMarkedAsInvalidSignature(_invalidSignaturePubkey[i], validatorId);
            unchecked {
                ++i;
            }
        }

        address ssvPool = staderConfig.getSSVPool();
        uint256 totalDefectedKeys = frontRunValidatorsLength + invalidSignatureValidatorsLength;
        if (totalDefectedKeys > 0) {
            _decreaseTotalActiveValidatorCount(totalDefectedKeys);
            ISSVPool(ssvPool).transferETHOfDefectiveKeysToSSPM(totalDefectedKeys);
        }
        ISSVPool(ssvPool).fullDepositOnBeaconChain(_readyToDepositPubkey);
    }

    /**
     * @notice register validator with SSV network
     * @param publicKey array of validator public keys
     * @param staderOperatorIds array of array of stader operator Ids
     * @param sharesData array of sharesData
     * @param cluster cluster array
     */
    function registerValidatorsWithSSV(
        bytes[] calldata publicKey,
        uint256[][] memory staderOperatorIds,
        bytes[] calldata sharesData,
        ISSVNetworkCore.Cluster[] memory cluster
    ) external {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        uint256 keyCount = publicKey.length;
        if (keyCount > batchSizeToRegisterValidatorFromSSV) {
            revert InputSizeIsMoreThanBatchSize();
        }
        if (keyCount != staderOperatorIds.length || keyCount != sharesData.length || keyCount != cluster.length) {
            revert MisMatchingInputKeysSize();
        }
        for (uint256 i; i < keyCount; ) {
            operatorIdssByPubkey[publicKey[i]] = staderOperatorIds[i];
            uint64[] memory ssvOperatorIds = _validateStaderOperators(staderOperatorIds[i]);
            ssvNetwork.registerValidator(publicKey[i], ssvOperatorIds, sharesData[i], 0, cluster[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice handling of fully withdrawn validators
     * @dev list of pubkeys reported by oracle
     * @param  _pubkeys array of withdrawn validators pubkey
     */
    function withdrawnValidators(bytes[] calldata _pubkeys) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STADER_ORACLE());
        uint256 withdrawnValidatorCount = _pubkeys.length;
        if (withdrawnValidatorCount > staderConfig.getWithdrawnKeyBatchSize()) {
            revert TooManyWithdrawnKeysReported();
        }
        for (uint256 i; i < withdrawnValidatorCount; ) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            if (validatorRegistry[validatorId].status != ValidatorStatus.DEPOSITED) {
                revert UNEXPECTED_STATUS();
            }
            _decreaseOperatorsKeyShareCount(_pubkeys[i]);
            validatorRegistry[validatorId].status = ValidatorStatus.WITHDRAWN;
            validatorRegistry[validatorId].withdrawnBlock = block.number;
            ISSVValidatorWithdrawalVault(validatorRegistry[validatorId].withdrawVaultAddress).settleFunds();
            emit ValidatorWithdrawn(_pubkeys[i], validatorId);
            unchecked {
                ++i;
            }
        }
        _decreaseTotalActiveValidatorCount(withdrawnValidatorCount);
    }

    function removeValidatorFromSSVNetwork(bytes[] calldata publicKey, ISSVNetworkCore.Cluster[] memory cluster)
        external
    {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        if (publicKey.length > batchSizeToRemoveValidatorFromSSV) {
            revert InputSizeIsMoreThanBatchSize();
        }
        for (uint256 i; i < publicKey.length; i++) {
            uint256 validatorId = validatorIdByPubkey[publicKey[i]];
            if (validatorRegistry[validatorId].status != ValidatorStatus.WITHDRAWN) {
                revert ValidatorNotWithdrawn();
            }
            ssvNetwork.removeValidator(
                publicKey[i],
                _getSSVOperatorIds(operatorIdssByPubkey[publicKey[i]]),
                cluster[i]
            );
        }
    }

    /**
     * @notice update the status of a validator to `PRE_DEPOSIT`
     * @dev only `SSV_POOL` contract can call
     * @param _pubkey pubkey of the validator
     */
    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SSV_POOL());
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        validatorRegistry[validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        emit MarkedValidatorStatusAsPreDeposit(_pubkey);
    }

    // function to set fee recipient address of all validator registered to SSV Network via this contract
    function setFeeRecipientAddress() external {
        ssvNetwork.setFeeRecipientAddress(staderConfig.getSSVSocializingPool());
    }

    /**
     * @notice increase the total active validator count
     * @dev only `SSV_POOL` calls it when it does the deposit of 1 ETH for validator
     * @param _count count to increase total active validator value
     */
    function increaseTotalActiveValidatorCount(uint256 _count) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SSV_POOL());
        totalActiveValidatorCount += _count;
        emit IncreasedTotalActiveValidatorCount(totalActiveValidatorCount);
    }

    /**
     * @notice update the next queued validator index by a count
     * @dev accept call from `SSV_POOL`
     * @param _nextQueuedValidatorIndex updated next index of queued validator
     */
    function updateNextQueuedValidatorIndex(uint256 _nextQueuedValidatorIndex) external {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SSV_POOL());
        nextQueuedValidatorIndex = _nextQueuedValidatorIndex;
        emit UpdatedNextQueuedValidatorIndex(nextQueuedValidatorIndex);
    }

    /**
     * @notice update maximum key to be added in a batch
     * @dev only `OPERATOR` role can call
     * @param _inputKeyCountLimit updated maximum key limit in the input
     */
    function updateInputKeyCountLimit(uint16 _inputKeyCountLimit) external override {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        inputKeyCountLimit = _inputKeyCountLimit;
        emit UpdatedInputKeyCountLimit(inputKeyCountLimit);
    }

    /**
     * @notice update the batch size of the keys to remove from SSV Network
     * @dev only `OPERATOR` role can call
     * @param _batchSizeToRemoveValidatorFromSSV count of pubkey to remove from SSV Network in a batch
     */
    function updateBatchSizeToRemoveValidatorFromSSV(uint64 _batchSizeToRemoveValidatorFromSSV) external override {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        batchSizeToRemoveValidatorFromSSV = _batchSizeToRemoveValidatorFromSSV;
        emit UpdatedBatchSizeToRemoveValidatorFromSSV(batchSizeToRemoveValidatorFromSSV);
    }

    /**
     * @notice update the batch size of the keys to register with SSV Network
     * @dev only `OPERATOR` role can call
     * @param _batchSizeToRegisterValidatorFromSSV count of pubkey to register with SSV Network in a batch
     */
    function updateBatchSizeToRegisterValidatorFromSSV(uint64 _batchSizeToRegisterValidatorFromSSV) external override {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        batchSizeToRegisterValidatorFromSSV = _batchSizeToRegisterValidatorFromSSV;
        emit UpdatedBatchSizeToRegisterValidatorWithSSV(batchSizeToRegisterValidatorFromSSV);
    }

    /**
     * @notice update the max number of verified validator keys reported by oracle
     * @dev only `OPERATOR` can call
     * @param _verifiedKeysBatchSize updated maximum verified key limit in the oracle input
     */
    function updateVerifiedKeysBatchSize(uint256 _verifiedKeysBatchSize) external {
        UtilLib.onlyOperatorRole(msg.sender, staderConfig);
        verifiedKeyBatchSize = _verifiedKeysBatchSize;
        emit UpdatedVerifiedKeyBatchSize(_verifiedKeysBatchSize);
    }

    /**
     * @notice update the address of staderConfig
     * @dev only `DEFAULT_ADMIN_ROLE` role can update
     */
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    // check for the validator being registered with SSV along with the PRE_DEPOSIT status
    function onlySSVRegisteredAndPreDepositValidator(bytes calldata _pubkey) external view {
        bool active = ssvNetworkViews.getValidator(address(this), _pubkey);
        if (!active) {
            revert ValidatorNotRegisteredWithSSV();
        }
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        _onlyPreDepositValidator(validatorId);
    }

    // check for duplicate keys in permissionless node registry
    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return validatorIdByPubkey[_pubkey] != 0;
    }

    // check for duplicate operator in permissionless node registry
    function isExistingOperator(address _operAddr) external view override returns (bool) {
        return operatorIDByAddress[_operAddr] != 0;
    }

    /**
     * @notice returns total active validator for SSV pool
     * @dev return the variable totalActiveValidatorCount
     * @return _validatorCount active validator count
     */
    function getTotalActiveValidatorCount() external view returns (uint256) {
        return totalActiveValidatorCount;
    }

    /**
     * @notice returns total queued keys for ssv pool
     * @return _validatorCount queued validator count
     */
    function getTotalQueuedValidatorCount() external view returns (uint256) {
        return nextValidatorId - nextQueuedValidatorIndex;
    }

    function getCollateralETH() external pure returns (uint256) {
        return COLLATERAL_ETH;
    }

    /**
     * @notice get the total count of keyshare for an operator
     * @param _operatorId Id of node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) public view override returns (uint256 _totalKeys) {
        _totalKeys = operatorStructById[_operatorId].keyShareCount;
    }

    /**
     * @notice returns the operator reward address
     * @param _operatorId operator Id
     */
    function getOperatorRewardAddress(uint256 _operatorId) external view override returns (address payable) {
        return operatorStructById[_operatorId].operatorRewardAddress;
    }

    /**
     * @notice returns operator key share count, start and end index parameters are not use while computing this
     * these params are defined to keep the function signature same as other pools
     * pass any number in these params to get the number of key share of the operator
     * @param _nodeOperator address of the operator
     * @param _startIndex parameter defined to maintain integrity across other pools
     * @param _endIndex parameter defined to maintain integrity across other pools
     */
    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (uint64) {
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        return operatorStructById[operatorId].keyShareCount;
    }

    // returns stader defined operator IDs of SSV operators running a validator
    function getOperatorsIdsForValidatorId(uint256 validatorId) external view returns (uint256[] memory) {
        return operatorIdssByPubkey[validatorRegistry[validatorId].pubkey];
    }

    /**
     * @notice Returns an array of active validators
     *
     * @param _pageNumber The page number of the results to fetch (starting from 1).
     * @param _pageSize The maximum number of items per page.
     *
     * @return An array of `Validator` objects representing the active validators.
     */
    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize) external view returns (Validator[] memory) {
        if (_pageNumber == 0) {
            revert PageNumberIsZero();
        }
        uint256 startIndex = (_pageNumber - 1) * _pageSize + 1;
        uint256 endIndex = startIndex + _pageSize;
        endIndex = endIndex > nextValidatorId ? nextValidatorId : endIndex;
        Validator[] memory validators = new Validator[](_pageSize);
        uint256 validatorCount;
        for (uint256 i = startIndex; i < endIndex; i++) {
            if (_isActiveValidator(i)) {
                validators[validatorCount] = validatorRegistry[i];
                validatorCount++;
            }
        }
        // If the result array isn't full, resize it to remove the unused elements
        assembly {
            mstore(validators, validatorCount)
        }

        return validators;
    }

    // checks if validator is active,
    //active validator are those having user deposit staked on beacon chain
    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        return (validator.status == ValidatorStatus.PRE_DEPOSIT || validator.status == ValidatorStatus.DEPOSITED);
    }

    function _verifyOperatorAndDepositAmount(uint256 _operatorId, uint256 _depositAmount) internal view {
        if (_operatorId == 0 || operatorStructById[_operatorId].operatorType) {
            revert OperatorNotOnboardOrPermissioned();
        }
        if (_depositAmount % COLLATERAL_ETH_PER_KEY_SHARE != 0) {
            revert InvalidCollateralAmount();
        }
    }

    function _verifyAddValidatorsKeysInputParams(
        uint256 _keyCount,
        uint256 _preDepositSigLen,
        uint256 _depositSigLen
    ) internal view {
        if (_keyCount != _preDepositSigLen || _keyCount != _depositSigLen) {
            revert MisMatchingInputKeysSize();
        }
        if (_keyCount == 0 || _keyCount > inputKeyCountLimit) {
            revert InvalidKeyCount();
        }
    }

    function _validateStaderOperators(uint256[] memory staderOperatorIds)
        internal
        returns (uint64[] memory ssvOperatorIds)
    {
        if (staderOperatorIds.length != CLUSTER_SIZE) {
            revert DifferentClusterSize();
        }
        ssvOperatorIds = new uint64[](CLUSTER_SIZE);
        uint256 totalCollateral;
        for (uint64 j = 0; j < CLUSTER_SIZE; j++) {
            SSVOperator storage operator = operatorStructById[staderOperatorIds[j]];
            bool enoughSDCollateral = ISDCollateral(staderConfig.getSDCollateral()).hasEnoughSDCollateral(
                msg.sender,
                POOL_ID,
                operator.keyShareCount + 1
            );
            if (!operator.operatorType && (operator.bondAmount < COLLATERAL_ETH_PER_KEY_SHARE || !enoughSDCollateral)) {
                revert NotSufficientCollateralPerKeyShare();
            }
            if (!operator.operatorType) {
                totalCollateral += COLLATERAL_ETH_PER_KEY_SHARE;
            }
            operator.bondAmount -= COLLATERAL_ETH_PER_KEY_SHARE;
            operator.keyShareCount += 1;
            ssvOperatorIds[j] = operatorStructById[staderOperatorIds[j]].operatorSSVID;
        }
        if (totalCollateral != COLLATERAL_ETH) {
            revert NotSufficientCollateralPerValidator();
        }
    }

    function _getSSVOperatorIds(uint256[] memory staderOperatorIds) internal returns (uint64[] memory ssvOperatorIds) {
        ssvOperatorIds = new uint64[](CLUSTER_SIZE);
        for (uint64 i = 0; i < CLUSTER_SIZE; i++) {
            ssvOperatorIds[i] = operatorStructById[staderOperatorIds[i]].operatorSSVID;
        }
    }

    function _onlyPreDepositValidator(uint256 _validatorId) internal view {
        if (validatorRegistry[_validatorId].status != ValidatorStatus.PRE_DEPOSIT) {
            revert UNEXPECTED_STATUS();
        }
    }

    // decreases the pool total active validator count
    function _decreaseTotalActiveValidatorCount(uint256 _count) internal {
        totalActiveValidatorCount -= _count;
        emit DecreasedTotalActiveValidatorCount(totalActiveValidatorCount);
    }

    function _decreaseOperatorsKeyShareCount(bytes calldata pubkey) internal {
        uint256[] memory operatorIds = operatorIdssByPubkey[pubkey];
        for (uint256 j; j < operatorIds.length; ) {
            operatorStructById[operatorIds[j]].keyShareCount -= 1;
            unchecked {
                ++j;
            }
        }
    }
}
