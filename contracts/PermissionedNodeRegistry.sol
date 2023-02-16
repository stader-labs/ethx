pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/INodeRegistry.sol';
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

    uint256 public initializedValidatorCount;
    uint256 public queuedValidatorCount;
    uint256 public activeValidatorCount;
    uint256 public withdrawnValidatorCount;

    address public override poolHelper;
    address public override vaultFactory;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override totalActiveOperators;
    uint256 public override KEY_DEPOSIT_LIMIT;
    uint256 public override operatorIdForExcessValidators;

    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;
    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override PERMISSIONED_NODE_REGISTRY_OWNER = keccak256('PERMISSIONED_NODE_REGISTRY_OWNER');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    struct Operator {
        bool active; // operator status
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        uint256 operatorId; //pool wise unique ID given by stader network
        uint256 nextQueuedValidatorIndex; //index of validator to pick from queuedValidators of a operator
        uint256 initializedValidatorCount; //validator whose keys added but not given pre signed msg for withdrawal
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    mapping(uint256 => Validator) public validatorRegistry;
    mapping(bytes => uint256) public override validatorIdByPubKey;

    mapping(address => Operator) public override operatorRegistry;
    mapping(uint256 => address) public override operatorByOperatorId;
    mapping(address => bool) public override permissionedNodeOperator;
    mapping(uint256 => uint256[]) public override operatorQueuedValidators;

    function initialize(
        address _adminOwner,
        address _vaultFactory,
        address _elRewardSocializePool
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_vaultFactory);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        __AccessControl_init_unchained();
        __Pausable_init();
        vaultFactory = _vaultFactory;
        elRewardSocializePool = _elRewardSocializePool;
        nextOperatorId = 1;
        nextValidatorId = 1;
        operatorIdForExcessValidators = 1;
        KEY_DEPOSIT_LIMIT = 100; //TODO decide on the value
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice white list the permissioned node operator
     * @dev only admin can call
     * @param _permissionedNOs array of permissioned NOs address
     */
    function whitelistPermissionedNOs(address[] calldata _permissionedNOs)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        for (uint256 i = 0; i < _permissionedNOs.length; i++) {
            Address.checkNonZeroAddress(_permissionedNOs[i]);
            permissionedNodeOperator[_permissionedNOs[i]] = true;
        }
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, check for whiteListOperator in case of permissionedPool
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
        onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_operatorRewardAddress);
        if (!permissionedNodeOperator[msg.sender]) revert NotAPermissionedNodeOperator();
        if (operatorRegistry[msg.sender].operatorId != 0) revert OperatorAlreadyOnBoarded();
        mevFeeRecipientAddress = elRewardSocializePool;
        _onboardOperator(_operatorName, _operatorRewardAddress);
        return mevFeeRecipientAddress;
    }

    /**
     * @notice add signing keys
     * @dev only accepts if bond of 4 ETH provided along with sufficient SD lockup
     * @param _validatorPubKey public key of validators
     * @param _validatorSignature signature of a validators
     * @param _depositDataRoot deposit data root of validators
     */
    function addValidatorKeys(
        bytes[] calldata _validatorPubKey,
        bytes[] calldata _validatorSignature,
        bytes32[] calldata _depositDataRoot
    ) external payable override whenNotPaused {
        if (!permissionedNodeOperator[msg.sender]) revert NotAPermissionedNodeOperator();
        if (_validatorPubKey.length != _validatorSignature.length || _validatorPubKey.length != _depositDataRoot.length)
            revert InvalidSizeOfInputKeys();
        uint256 keyCount = _validatorPubKey.length;
        if (keyCount == 0) revert NoKeysProvided();
        if (
            (getTotalValidatorKeys(msg.sender) - operatorRegistry[msg.sender].withdrawnValidatorCount + keyCount) >
            KEY_DEPOSIT_LIMIT
        ) revert maxKeyLimitReached();
        Operator storage operator = operatorRegistry[msg.sender];
        uint256 operatorId = operator.operatorId;
        if (operatorId == 0) revert OperatorNotOnBoarded();
        //TODO call SDlocker to check enough SD
        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_validatorPubKey[i], _validatorSignature[i], _depositDataRoot[i], operatorId);
        }
        initializedValidatorCount += keyCount;
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT after receiving pre-signed messages for withdrawal
     * @dev only admin can call
     * @param _pubKeys array of pubKeys ready to be moved to PRE_DEPOSIT state
     */
    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys)
        external
        override
        whenNotPaused
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        for (uint256 i = 0; i < _pubKeys.length; i++) {
            uint256 validatorId = validatorIdByPubKey[_pubKeys[i]];
            if (validatorId == 0) revert PubKeyDoesNotExist();
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubKeys[i], validatorId);
        }
        initializedValidatorCount -= _pubKeys.length;
        queuedValidatorCount += _pubKeys.length;
    }

    /**
     * @notice operator selection logic
     * @dev first iteration is round robin based on capacity,
     * second iteration exhaust the capacity in sequential manner and
     * update the operatorId to pick operator for next sequence in next cycle
     * @param _validatorRequiredToDeposit validator to deposit with permissioned pool
     * @return operatorWiseValidatorsToDeposit operator wise count of validator to deposit
     */
    function computeOperatorWiseValidatorsToDeposit(uint256 _validatorRequiredToDeposit)
        external
        override
        onlyRole(STADER_NETWORK_POOL)
        returns (uint256[] memory operatorWiseValidatorsToDeposit)
    {
        uint256 totalOperators = nextOperatorId - 1;
        uint256 validatorPerOperator = _validatorRequiredToDeposit / totalActiveOperators;
        uint256[] memory operatorCapacity;
        uint256 totalValidatorToDeposit;
        for (uint256 i = 1; i < totalOperators; i++) {
            address operator = operatorByOperatorId[i];
            if (!operatorRegistry[operator].active) continue;
            operatorCapacity[i] = operatorRegistry[operator].queuedValidatorCount;
            operatorWiseValidatorsToDeposit[i] = Math.min(operatorCapacity[i], validatorPerOperator);
            totalValidatorToDeposit += operatorWiseValidatorsToDeposit[i];
            operatorCapacity[i] -= operatorWiseValidatorsToDeposit[i];
        }

        // check for more validators to deposit and select operators with excess supply in a sequential order
        // and update the starting index of operator for next sequence after every iteration
        if (_validatorRequiredToDeposit > totalValidatorToDeposit) {
            uint256 remainingValidatorsToDeposit = _validatorRequiredToDeposit - totalValidatorToDeposit;
            uint256[] memory operatorIdQueue;
            uint256 counter;
            for (uint256 i = operatorIdForExcessValidators; i <= totalOperators; i++) {
                operatorIdQueue[counter++] = i;
            }
            for (uint256 i = 1; i < operatorIdForExcessValidators; i++) {
                operatorIdQueue[counter++] = i;
            }

            for (uint256 i = 0; i < operatorIdQueue.length; i++) {
                address operator = operatorByOperatorId[operatorIdQueue[i]];
                if (!operatorRegistry[operator].active) continue;
                uint256 moreValidatorToDepositForOperator = Math.min(
                    operatorCapacity[operatorIdQueue[i]],
                    remainingValidatorsToDeposit
                );
                operatorWiseValidatorsToDeposit[operatorIdQueue[i]] += moreValidatorToDepositForOperator;
                remainingValidatorsToDeposit -= moreValidatorToDepositForOperator;
                if (remainingValidatorsToDeposit == 0) {
                    operatorIdForExcessValidators = operatorIdQueue[(i + 1) % operatorIdQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice activate a node operator for running new validator clients
     * @dev only accept call from admin
     * @param _nodeOperator address of the operator to activate
     */
    function activateNodeOperator(address _nodeOperator) external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        onlyOnboardedOperator(msg.sender);
        if (operatorRegistry[_nodeOperator].active) revert OperatorAlreadyActive();
        operatorRegistry[_nodeOperator].active = true;
        queuedValidatorCount += operatorRegistry[_nodeOperator].queuedValidatorCount;
        totalActiveOperators++;
    }

    /**
     * @notice deactivate a node operator from running new validator clients
     * @dev only accept call from admin
     * @param _nodeOperator address of the operator to deactivate
     */
    function deactivateNodeOperator(address _nodeOperator)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        onlyOnboardedOperator(msg.sender);
        if (!operatorRegistry[_nodeOperator].active) revert OperatorNotActive();
        operatorRegistry[_nodeOperator].active = false;
        queuedValidatorCount -= operatorRegistry[_nodeOperator].queuedValidatorCount;
        totalActiveOperators--;
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _nodeOperator operator ID
     */
    function reduceQueuedValidatorsCount(address _nodeOperator) external override onlyRole(STADER_NETWORK_POOL) {
        onlyOnboardedOperator(msg.sender);
        if (operatorRegistry[_nodeOperator].queuedValidatorCount == 0) revert NoQueuedValidatorLeft();
        operatorRegistry[_nodeOperator].queuedValidatorCount--;
        emit ReducedQueuedValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].queuedValidatorCount
        );
    }

    /**
     * @notice increase the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _nodeOperator operator ID
     */
    function incrementActiveValidatorsCount(address _nodeOperator) external override onlyRole(STADER_NETWORK_POOL) {
        onlyOnboardedOperator(msg.sender);
        operatorRegistry[_nodeOperator].activeValidatorCount++;
        emit IncrementedActiveValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].activeValidatorCount
        );
    }

    /**
     * @notice reduce the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _nodeOperator operator ID
     */
    function reduceActiveValidatorsCount(address _nodeOperator) external override onlyRole(STADER_NETWORK_POOL) {
        onlyOnboardedOperator(msg.sender);
        if (operatorRegistry[_nodeOperator].activeValidatorCount == 0) revert NoActiveValidatorLeft();
        operatorRegistry[_nodeOperator].activeValidatorCount--;
        emit ReducedActiveValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].activeValidatorCount
        );
    }

    /**
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _nodeOperator operator ID
     */
    function incrementWithdrawValidatorsCount(address _nodeOperator) external override onlyRole(STADER_NETWORK_POOL) {
        onlyOnboardedOperator(msg.sender);
        operatorRegistry[_nodeOperator].withdrawnValidatorCount++;
        emit IncrementedWithdrawnValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].withdrawnValidatorCount
        );
    }

    /**
     * @notice update the `nextQueuedValidatorIndex` for operator
     * @dev only stader network can call
     * @param _nodeOperator address of the node operator
     * @param _nextQueuedValidatorIndex updated next index of queued validator per operator
     */
    function updateQueuedValidatorIndex(address _nodeOperator, uint256 _nextQueuedValidatorIndex)
        external
        override
        onlyRole(STADER_NETWORK_POOL)
    {
        onlyOnboardedOperator(msg.sender);
        operatorRegistry[_nodeOperator].nextQueuedValidatorIndex = _nextQueuedValidatorIndex;
        emit UpdatedQueuedValidatorIndex(_nodeOperator, _nextQueuedValidatorIndex);
    }

    /**
     * @notice update the status of a validator
     * @dev only stader network can call
     * @param _pubKey public key of the validator
     * @param _status updated status of validator
     */
    function updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status)
        external
        override
        onlyRole(STADER_NETWORK_POOL)
    {
        uint256 validatorId = validatorIdByPubKey[_pubKey];
        if (validatorId == 0) revert PubKeyDoesNotExist();
        validatorRegistry[validatorId].status = _status;
        emit UpdatedValidatorStatus(_pubKey, _status);
    }

    /**
     * @notice updates the address of pool helper
     * @dev only NOs registry can call
     * @param _staderPoolSelector address of poolHelper
     */
    function updatePoolSelector(address _staderPoolSelector)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_staderPoolSelector);
        poolHelper = _staderPoolSelector;
        emit UpdatedPoolHelper(_staderPoolSelector);
    }

    /**
     * @notice update the address of vault factory
     * @dev only admin can call
     * @param _vaultFactory address of vault factory
     */
    function updateVaultAddress(address _vaultFactory) external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        Address.checkNonZeroAddress(_vaultFactory);
        vaultFactory = _vaultFactory;
        emit UpdatedVaultFactory(_vaultFactory);
    }

    /**
     * @notice update the reward address of an operator
     * @dev only operator msg.sender can update
     * @param _rewardAddress new reward address
     */
    function updateOperatorRewardAddress(address payable _rewardAddress) external override {
        Address.checkNonZeroAddress(_rewardAddress);
        onlyOnboardedOperator(msg.sender);
        operatorRegistry[msg.sender].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorRewardAddress(msg.sender, _rewardAddress);
    }

    /**
     * @notice changes the name of operator
     * @dev only operator msg.sender can update
     * @param _operatorName new operator name
     */
    function updateOperatorName(string calldata _operatorName) external override {
        onlyValidName(_operatorName);
        onlyOnboardedOperator(msg.sender);
        operatorRegistry[msg.sender].operatorName = _operatorName;
        emit UpdatedOperatorName(msg.sender, _operatorName);
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

    function getValidator(bytes memory _pubkey) external view returns (Validator memory) {
        return validatorRegistry[validatorIdByPubKey[_pubkey]];
    }

    function getValidator(uint256 _validatorId) external view returns (Validator memory) {
        return validatorRegistry[_validatorId];
    }

    /**
     * @notice returns the total operator count
     */
    function getOperatorCount() public view override returns (uint256 _operatorCount) {
        _operatorCount = nextOperatorId - 1;
    }

    function getTotalValidatorCount() public view override returns (uint256 _validatorCount) {
        return
            this.getInitializedValidatorCount() +
            this.getQueuedValidatorCount() +
            this.getActiveValidatorCount() +
            this.getWithdrawnValidatorCount();
    }

    function getInitializedValidatorCount() public view override returns (uint256 _validatorCount) {
        return initializedValidatorCount;
    }

    function getQueuedValidatorCount() public view override returns (uint256 _validatorCount) {
        return queuedValidatorCount;
    }

    function getActiveValidatorCount() public view override returns (uint256 _validatorCount) {
        return activeValidatorCount;
    }

    function getWithdrawnValidatorCount() public view override returns (uint256 _validatorCount) {
        return withdrawnValidatorCount;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add queued, active and withdrawn validator to get total validators keys
     * @param _nodeOperator owner of operator
     */
    function getTotalValidatorKeys(address _nodeOperator) public view returns (uint256 _totalKeys) {
        onlyOnboardedOperator(_nodeOperator);
        _totalKeys =
            operatorRegistry[_nodeOperator].initializedValidatorCount +
            operatorRegistry[_nodeOperator].queuedValidatorCount +
            operatorRegistry[_nodeOperator].activeValidatorCount +
            operatorRegistry[_nodeOperator].withdrawnValidatorCount;
    }

    function _onboardOperator(string calldata _operatorName, address payable _operatorRewardAddress) internal {
        operatorRegistry[msg.sender] = Operator(
            true,
            _operatorName,
            _operatorRewardAddress,
            nextOperatorId,
            0,
            0,
            0,
            0,
            0
        );
        operatorByOperatorId[nextOperatorId] = msg.sender;
        totalActiveOperators++;
        emit OnboardedOperator(msg.sender, nextOperatorId);
        nextOperatorId++;
    }

    function _addValidatorKey(
        bytes calldata _pubKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        uint256 _operatorId
    ) internal {
        uint256 totalKeys = getTotalValidatorKeys(msg.sender);
        address withdrawVault = IVaultFactory(vaultFactory).computeWithdrawVaultAddress(2, _operatorId, totalKeys);
        bytes memory withdrawCredential = IVaultFactory(vaultFactory).getValidatorWithdrawCredential(withdrawVault);
        _validateKeys(_pubKey, withdrawCredential, _signature, _depositDataRoot);
        IVaultFactory(vaultFactory).deployWithdrawVault(2, _operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            false,
            _pubKey,
            _signature,
            withdrawCredential,
            _operatorId,
            0
        );
        validatorIdByPubKey[_pubKey] = nextValidatorId;
        operatorRegistry[msg.sender].initializedValidatorCount++;
        emit AddedKeys(msg.sender, _pubKey, nextValidatorId);
        nextValidatorId++;
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorQueuedValidators[operatorId].push(_validatorId);
        address nodeOperator = operatorByOperatorId[operatorId];
        operatorRegistry[nodeOperator].initializedValidatorCount--;
        operatorRegistry[nodeOperator].queuedValidatorCount++;
    }

    function _validateKeys(
        bytes calldata pubkey,
        bytes memory withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) private pure {
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        bytes32 node = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkey_root, withdrawal_credentials)),
                sha256(abi.encodePacked(DEPOSIT_SIZE_IN_GWEI_LE64, bytes24(0), signature_root))
            )
        );

        // Verify computed and expected deposit data roots match
        require(
            node == deposit_data_root,
            'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
        );
    }

    function onlyOnboardedOperator(address _nodeOperator) internal view {
        if (operatorRegistry[_nodeOperator].operatorId == 0) revert OperatorNotOnBoarded();
    }

    function onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }
}
