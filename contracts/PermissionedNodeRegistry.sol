pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPermissionedNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionedNodeRegistry is
    INodeRegistry,
    IPermissionedNodeRegistry,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using Math for uint256;

    uint8 public constant override poolId = 2;
    uint64 private constant pubkey_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override maxKeyPerOperator;
    uint256 public override BATCH_KEY_DEPOSIT_LIMIT;
    uint256 public override operatorIdForExcessDeposit;

    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');
    bytes32 public constant override VALIDATOR_STATUS_ROLE = keccak256('VALIDATOR_STATUS_ROLE');
    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override DEACTIVATE_OPERATOR_ROLE = keccak256('DEACTIVATE_OPERATOR_ROLE');
    bytes32 public constant override PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');
    bytes32 public constant override PERMISSIONED_NODE_REGISTRY_OWNER = keccak256('PERMISSIONED_NODE_REGISTRY_OWNER');

    struct Validator {
        ValidatorStatus status; // state of validator
        bool isFrontRun; // set to true by DAO if validator get front deposit
        bytes pubkey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        address withdrawVaultAddress; //eth1 withdrawal address for validator
        uint256 operatorId; // stader network assigned Id
    }

    struct Operator {
        bool active; // operator status
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        address operatorAddress; //address of operator to interact with stader
        uint256 nextQueuedValidatorIndex; //index of validator to pick from queuedValidators of a operator
        uint256 initializedValidatorCount; //validator whose keys added but not given pre signed msg for withdrawal
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    // mapping of validator ID and Validator struct
    mapping(uint256 => Validator) public override validatorRegistry;
    // mapping of bytes public key and validator Id
    mapping(bytes => uint256) public override validatorIdBypubkey;
    // mapping of operaot ID and Operator struct
    mapping(uint256 => Operator) public override operatorStructById;
    // mapping of operator address and operator Id
    mapping(address => uint256) public override operatorIDByAddress;

    // mapping of whitelisted permissioned node operator
    mapping(address => bool) public override permissionList;
    //mapping of operator wise queued validator IDs arrays
    mapping(uint256 => uint256[]) public override operatorQueuedValidators;

    function initialize(
        address _adminOwner,
        address _vaultFactoryAddress,
        address _elRewardSocializePool
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        __AccessControl_init_unchained();
        __Pausable_init();
        vaultFactoryAddress = _vaultFactoryAddress;
        elRewardSocializePool = _elRewardSocializePool;
        nextOperatorId = 1;
        nextValidatorId = 1;
        operatorIdForExcessDeposit = 1;
        BATCH_KEY_DEPOSIT_LIMIT = 100;
        maxKeyPerOperator = 1000; //TODO decide on the value
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice white list the permissioned node operator
     * @dev only admin can call, whitelisting a one way change there is no blacklisting
     * @param _permissionedNOs array of permissioned NOs address
     */
    function whitelistPermissionedNOs(address[] calldata _permissionedNOs)
        external
        override
        onlyRole(STADER_MANAGER_BOT)
    {
        for (uint256 i = 0; i < _permissionedNOs.length; i++) {
            Address.checkNonZeroAddress(_permissionedNOs[i]);
            permissionList[_permissionedNOs[i]] = true;
        }
    }

    /**
     * @notice onboard a node operator
     * @dev only whitelisted NOs can call
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address for all validator clients
     */
    function onboardNodeOperator(string calldata _operatorName, address payable _operatorRewardAddress)
        external
        override
        whenNotPaused
        returns (address mevFeeRecipientAddress)
    {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_operatorRewardAddress);
        if (!permissionList[msg.sender]) revert NotAPermissionedNodeOperator();
        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();
        mevFeeRecipientAddress = elRewardSocializePool;
        _onboardOperator(_operatorName, _operatorRewardAddress);
        return mevFeeRecipientAddress;
    }

    /**
     * @notice add signing keys
     * @dev only accepts if bond of 4 ETH per key provided along with sufficient SD lockup
     * @param _validatorpubkey public key of validators
     * @param _validatorSignature signature of a validators
     */
    function addValidatorKeys(bytes[] calldata _validatorpubkey, bytes[] calldata _validatorSignature)
        external
        override
        whenNotPaused
    {
        if (_validatorpubkey.length != _validatorSignature.length) revert InvalidSizeOfInputKeys();

        uint256 keyCount = _validatorpubkey.length;
        if (keyCount == 0 || keyCount > BATCH_KEY_DEPOSIT_LIMIT) revert InvalidCountOfKeys();

        uint256 operatorId = _onlyOnboardedOperator(msg.sender);

        Operator memory operator = operatorStructById[operatorId];

        uint256 totalNonWithdrawnKeys = this.getOperatorTotalKeys(msg.sender) - operator.withdrawnValidatorCount;

        if ((totalNonWithdrawnKeys + keyCount) > maxKeyPerOperator) revert maxKeyLimitReached();

        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughXSDCollateral(msg.sender, poolId, totalNonWithdrawnKeys + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_validatorpubkey[i], _validatorSignature[i], operatorId);
        }
        _increaseInitializedValidatorCount(operator, keyCount);
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT
     * after receiving pre-signed messages for withdrawal & offchain daemon verification
     * @dev only admin can call
     * @param _pubkeys array of pubkeys ready to be moved to PRE_DEPOSIT state
     */
    function markValidatorReadyToDeposit(bytes[] calldata _pubkeys)
        external
        override
        whenNotPaused
        onlyRole(STADER_MANAGER_BOT)
    {
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            uint256 validatorId = validatorIdBypubkey[_pubkeys[i]];
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubkeys[i], validatorId);
        }
    }

    /**
     * @notice operator selection logic
     * @dev first iteration is round robin based on capacity,
     * second iteration exhaust the capacity in sequential manner and
     * update the operatorId to pick operator for next sequence in next cycle
     * all array start with index 1
     * @param numValidators validator to deposit with permissioned pool
     * @return selectedOperatorCapacity operator wise count of validator to deposit
     */
    function computeOperatorAllocationForDeposit(uint256 numValidators)
        external
        override
        onlyRole(PERMISSIONED_POOL)
        returns (uint256[] memory selectedOperatorCapacity)
    {
        // nextOperatorId is total operator count plus 1
        selectedOperatorCapacity = new uint256[](nextOperatorId);
        uint256 activeOperatorCount = this.getTotalActiveOperatorCount();

        if (activeOperatorCount == 0) revert NOActiveOperator();

        uint256 validatorPerOperator = numValidators / activeOperatorCount;
        uint256[] memory remainingOperatorCapacity = new uint256[](nextOperatorId);
        uint256 totalValidatorToDeposit;

        for (uint256 i = 1; i < nextOperatorId; i++) {
            if (!operatorStructById[i].active) continue;
            remainingOperatorCapacity[i] = operatorStructById[i].queuedValidatorCount;
            selectedOperatorCapacity[i] = Math.min(remainingOperatorCapacity[i], validatorPerOperator);
            totalValidatorToDeposit += selectedOperatorCapacity[i];
            remainingOperatorCapacity[i] -= selectedOperatorCapacity[i];
        }

        // check for more validators to deposit and select operators with excess supply in a sequential order
        // and update the starting index of operator for next sequence after every iteration
        if (numValidators > totalValidatorToDeposit) {
            uint256 totalOperators = nextOperatorId - 1;
            uint256 remainingValidatorsToDeposit = numValidators - totalValidatorToDeposit;
            uint256[] memory operatorIdQueue = new uint256[](totalOperators);
            uint256 counter;
            for (uint256 i = operatorIdForExcessDeposit; i <= totalOperators; i++) {
                operatorIdQueue[counter++] = i;
            }
            for (uint256 i = 1; i < operatorIdForExcessDeposit; i++) {
                operatorIdQueue[counter++] = i;
            }

            for (uint256 i = 0; i < totalOperators; i++) {
                if (!operatorStructById[operatorIdQueue[i]].active) continue;
                uint256 newSelectedCapacity = Math.min(
                    remainingOperatorCapacity[operatorIdQueue[i]],
                    remainingValidatorsToDeposit
                );
                selectedOperatorCapacity[operatorIdQueue[i]] += newSelectedCapacity;
                remainingValidatorsToDeposit -= newSelectedCapacity;
                if (remainingValidatorsToDeposit == 0) {
                    operatorIdForExcessDeposit = operatorIdQueue[(i + 1) % operatorIdQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice deactivate a node operator from running new validator clients
     * @dev only accept call from address having `DEACTIVATE_OPERATOR_ROLE` role
     * @param _operatorID ID of the operator to deactivate
     */
    function deactivateNodeOperator(uint256 _operatorID) external override onlyRole(DEACTIVATE_OPERATOR_ROLE) {
        operatorStructById[_operatorID].active = false;
    }

    /**
     * @notice reduce the queued validator count and increase active validator count for a operator
     * @dev only accept call from permissioned pool contract
     * @param _operatorID operator ID
     */
    function updateQueuedAndActiveValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(PERMISSIONED_POOL)
    {
        Operator memory operator = operatorStructById[_operatorID];
        operator.queuedValidatorCount -= _count;
        operator.activeValidatorCount += _count;
        emit UpdatedQueuedAndActiveValidatorsCount(
            _operatorID,
            operator.queuedValidatorCount,
            operator.activeValidatorCount
        );
    }

    /**
     * @notice reduce the active validator count and increase withdrawn validator count for a operator
     * @dev only accept call from accounts having `STADER_ORACLE` role
     * @param _operatorID operator ID
     */
    function updateActiveAndWithdrawnValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(STADER_ORACLE)
    {
        Operator memory operator = operatorStructById[_operatorID];
        operator.activeValidatorCount -= _count;
        operator.withdrawnValidatorCount += _count;
        emit UpdatedActiveAndWithdrawnValidatorsCount(
            _operatorID,
            operator.activeValidatorCount,
            operator.withdrawnValidatorCount
        );
    }

    /**
     * @notice update the `nextQueuedValidatorIndex` for operator
     * @dev only permissioned pool can call
     * @param _operatorID ID of the node operator
     * @param _nextQueuedValidatorIndex updated next index of queued validator per operator
     */
    function updateQueuedValidatorIndex(uint256 _operatorID, uint256 _nextQueuedValidatorIndex)
        external
        override
        onlyRole(PERMISSIONED_POOL)
    {
        operatorStructById[_operatorID].nextQueuedValidatorIndex = _nextQueuedValidatorIndex;
        emit UpdatedQueuedValidatorIndex(_operatorID, _nextQueuedValidatorIndex);
    }

    /**
     * @notice update the isFrontRun value to true
     * @dev only permissioned pool can call
     * @param _validatorIds array of validator IDs which got front running deposit
     */
    function updateFrontRunValidator(uint256[] calldata _validatorIds) external override onlyRole(PERMISSIONED_POOL) {
        for (uint256 i = 0; i < _validatorIds.length; i++) {
            validatorRegistry[_validatorIds[i]].isFrontRun = true;
        }
    }

    /**
     * @notice update the status of a validator
     * @dev only `VALIDATOR_STATUS_ROLE` role can call
     * @param _pubkey public key of the validator
     * @param _status updated status of validator
     */

    //TODO decide on role as oracle might also call it along with permissioned pool
    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status)
        external
        override
        onlyRole(VALIDATOR_STATUS_ROLE)
    {
        uint256 validatorId = validatorIdBypubkey[_pubkey];
        if (validatorId == 0) revert pubkeyDoesNotExist();
        validatorRegistry[validatorId].status = _status;
        emit UpdatedValidatorStatus(_pubkey, _status);
    }

    /**
     * @notice update the address of vault factory
     * @dev only admin can call
     * @param _vaultFactoryAddress address of vault factory
     */
    function updateVaultFactoryAddress(address _vaultFactoryAddress)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        vaultFactoryAddress = _vaultFactoryAddress;
        emit UpdatedVaultFactoryAddress(_vaultFactoryAddress);
    }

    /**
     * @notice update the name and reward address of an operator
     * @dev only operator msg.sender can update
     * @param _operatorName new Name of the operator
     * @param _rewardAddress new reward address
     */
    function updateOperatorDetails(string calldata _operatorName, address payable _rewardAddress) external override {
        _onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_rewardAddress);

        _onlyOnboardedOperator(msg.sender);
        uint256 operatorId = operatorIDByAddress[msg.sender];
        operatorStructById[operatorId].operatorName = _operatorName;
        operatorStructById[operatorId].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorDetails(msg.sender, _operatorName, _rewardAddress);
    }

    /**
     * @notice update the maximum non withdrawn key limit per operator
     * @dev only admin can call
     * @param _maxKeyPerOperator updated maximum non withdrawn key per operator limit
     */
    function updateMaxKeyPerOperator(uint256 _maxKeyPerOperator)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        maxKeyPerOperator = _maxKeyPerOperator;
        emit UpdatedMaxKeyPerOperator(maxKeyPerOperator);
    }

    /**
     * @notice update maximum key to be deposited in a batch
     * @dev only admin can call
     * @param _batchKeyDepositLimit updated maximum key limit in a batch
     */
    function updateBatchKeyDepositLimit(uint256 _batchKeyDepositLimit)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        BATCH_KEY_DEPOSIT_LIMIT = _batchKeyDepositLimit;
        emit UpdatedBatchKeyDepositLimit(BATCH_KEY_DEPOSIT_LIMIT);
    }

    /**
     * @notice returns the total active operator count
     */
    function getTotalActiveOperatorCount() external view override returns (uint256 _activeOperatorCount) {
        for (uint256 i = 1; i < nextOperatorId; i++) {
            if (operatorStructById[i].active) {
                _activeOperatorCount++;
            }
        }
    }

    /**
     * @notice computes total queued keys for permissioned pool
     * @dev compute by looping over all the queued keys of all operators
     * @return _validatorCount queued validator count
     */
    function getTotalQueuedValidatorCount() public view override returns (uint256 _validatorCount) {
        for (uint256 i = 1; i < nextOperatorId; i++) {
            if (operatorStructById[i].active) {
                _validatorCount += operatorStructById[i].queuedValidatorCount;
            }
        }
    }

    /**
     * @notice computes total active keys for permissioned pool
     * @dev compute by looping over all the active keys of all operators
     * @return _validatorCount active validator count
     */
    function getTotalActiveValidatorCount() public view override returns (uint256 _validatorCount) {
        for (uint256 i = 1; i < nextOperatorId; i++) {
            _validatorCount += operatorStructById[i].activeValidatorCount;
        }
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add initialized, queued, active and withdrawn validator key count to get total validators keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalKeys(address _nodeOperator) external view override returns (uint256 _totalKeys) {
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        _totalKeys =
            operatorStructById[operatorId].initializedValidatorCount +
            operatorStructById[operatorId].queuedValidatorCount +
            operatorStructById[operatorId].activeValidatorCount +
            operatorStructById[operatorId].withdrawnValidatorCount;
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        _unpause();
    }

    function _onboardOperator(string calldata _operatorName, address payable _operatorRewardAddress) internal {
        operatorStructById[nextOperatorId] = Operator(
            true,
            _operatorName,
            _operatorRewardAddress,
            msg.sender,
            0,
            0,
            0,
            0,
            0
        );
        operatorIDByAddress[msg.sender] = nextOperatorId;
        nextOperatorId++;
        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    function _addValidatorKey(
        bytes calldata _pubkey,
        bytes calldata _signature,
        uint256 _operatorId
    ) internal {
        _validateKeys(_pubkey, _signature);
        uint256 totalKeys = this.getOperatorTotalKeys(msg.sender);

        address withdrawVault = IVaultFactory(vaultFactoryAddress).deployWithdrawVault(poolId, _operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            false,
            _pubkey,
            _signature,
            withdrawVault,
            _operatorId
        );
        validatorIdBypubkey[_pubkey] = nextValidatorId;
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubkey, nextValidatorId - 1);
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorQueuedValidators[operatorId].push(_validatorId);
        _updateInitializedAndQueuedValidatorCount(operatorId);
    }

    function _validateKeys(bytes calldata pubkey, bytes calldata signature) private view {
        if (pubkey.length != pubkey_LENGTH) revert InvalidLengthOfpubkey();
        if (signature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (validatorIdBypubkey[pubkey] != 0) revert pubkeyAlreadyExist();
    }

    function _onlyOnboardedOperator(address _operAddr) internal view returns (uint256 _operatorId) {
        _operatorId = operatorIDByAddress[_operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
    }

    function _increaseInitializedValidatorCount(Operator memory _operator, uint256 _count) internal pure {
        _operator.initializedValidatorCount += _count;
    }

    function _updateInitializedAndQueuedValidatorCount(uint256 _operatorId) internal view {
        Operator memory operator = operatorStructById[_operatorId];
        operator.initializedValidatorCount--;
        operator.queuedValidatorCount++;
    }

    function _onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }
}
