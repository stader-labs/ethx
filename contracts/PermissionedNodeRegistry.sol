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
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;

    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override KEY_DEPOSIT_LIMIT;
    uint256 public override operatorIdForExcessValidators;

    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override PERMISSIONED_POOL_CONTRACT = keccak256('PERMISSIONED_POOL_CONTRACT');
    bytes32 public constant override PERMISSIONED_NODE_REGISTRY_OWNER = keccak256('PERMISSIONED_NODE_REGISTRY_OWNER');

    struct Validator {
        ValidatorStatus status; // state of validator
        bytes pubKey; //public Key of the validator
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

    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorIdByPubKey;

    mapping(uint256 => Operator) public override operatorStructById;
    mapping(address => uint256) public override operatorIDByAddress;

    mapping(address => bool) public override permissionList;
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
        operatorIdForExcessValidators = 1;
        KEY_DEPOSIT_LIMIT = 100; //TODO decide on the value
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
        if (!permissionList[msg.sender]) revert NotAPermissionedNodeOperator();
        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();
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
    ) external override whenNotPaused {
        onlyOnboardedOperator(msg.sender);
        if (_validatorPubKey.length != _validatorSignature.length || _validatorPubKey.length != _depositDataRoot.length)
            revert InvalidSizeOfInputKeys();

        uint256 keyCount = _validatorPubKey.length;
        if (keyCount == 0) revert NoKeysProvided();

        uint256 operatorId = operatorIDByAddress[msg.sender];
        uint256 totalKeysExceptWithdrawn = this.getOperatorTotalKeys(operatorId) -
            operatorStructById[operatorId].withdrawnValidatorCount;

        if ((totalKeysExceptWithdrawn + keyCount) > KEY_DEPOSIT_LIMIT) revert maxKeyLimitReached();

        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughXSDCollateral(msg.sender, poolId, totalKeysExceptWithdrawn + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_validatorPubKey[i], _validatorSignature[i], _depositDataRoot[i], operatorId);
        }
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT
     * after receiving pre-signed messages for withdrawal & offchain daemon verification
     * @dev only admin can call
     * @param _pubKeys array of pubKeys ready to be moved to PRE_DEPOSIT state
     */
    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys)
        external
        override
        whenNotPaused
        onlyRole(STADER_MANAGER_BOT)
    {
        for (uint256 i = 0; i < _pubKeys.length; i++) {
            uint256 validatorId = validatorIdByPubKey[_pubKeys[i]];
            if (validatorId == 0) revert PubKeyDoesNotExist();
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubKeys[i], validatorId);
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
        onlyRole(PERMISSIONED_POOL_CONTRACT)
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
            for (uint256 i = operatorIdForExcessValidators; i <= totalOperators; i++) {
                operatorIdQueue[counter++] = i;
            }
            for (uint256 i = 1; i < operatorIdForExcessValidators; i++) {
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
                    operatorIdForExcessValidators = operatorIdQueue[(i + 1) % operatorIdQueue.length];
                    break;
                }
            }
        }
    }

    /**
     * @notice activate a node operator for running new validator clients
     * @dev only accept call from admin
     * @param _operatorID ID of the operator to activate
     */
    function activateNodeOperator(uint256 _operatorID) external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        if (operatorStructById[_operatorID].active) revert OperatorAlreadyActive();
        operatorStructById[_operatorID].active = true;
    }

    /**
     * @notice deactivate a node operator from running new validator clients
     * @dev only accept call from admin
     * @param _operatorID ID of the operator to deactivate
     */
    function deactivateNodeOperator(uint256 _operatorID) external override onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        if (!operatorStructById[_operatorID].active) revert OperatorNotActive();
        operatorStructById[_operatorID].active = false;
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorID operator ID
     */
    function reduceQueuedValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(PERMISSIONED_POOL_CONTRACT)
    {
        operatorStructById[_operatorID].queuedValidatorCount -= _count;
        emit ReducedQueuedValidatorsCount(_operatorID, operatorStructById[_operatorID].queuedValidatorCount);
    }

    /**
     * @notice increase the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorID operator ID
     */
    function increaseActiveValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(PERMISSIONED_POOL_CONTRACT)
    {
        operatorStructById[_operatorID].activeValidatorCount += _count;
        emit IncrementedActiveValidatorsCount(_operatorID, operatorStructById[_operatorID].activeValidatorCount);
    }

    /**
     * @notice reduce the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorID operator ID
     */
    function reduceActiveValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(PERMISSIONED_POOL_CONTRACT)
    {
        operatorStructById[_operatorID].activeValidatorCount -= _count;
        emit ReducedActiveValidatorsCount(_operatorID, operatorStructById[_operatorID].activeValidatorCount);
    }

    /**
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _operatorID operator ID
     */
    function increaseWithdrawnValidatorsCount(uint256 _operatorID, uint256 _count)
        external
        override
        onlyRole(STADER_NETWORK_POOL)
    {
        operatorStructById[_operatorID].withdrawnValidatorCount += _count;
        emit IncrementedWithdrawnValidatorsCount(_operatorID, operatorStructById[_operatorID].withdrawnValidatorCount);
    }

    /**
     * @notice update the `nextQueuedValidatorIndex` for operator
     * @dev only stader network can call
     * @param _operatorID ID of the node operator
     * @param _nextQueuedValidatorIndex updated next index of queued validator per operator
     */
    function updateQueuedValidatorIndex(uint256 _operatorID, uint256 _nextQueuedValidatorIndex)
        external
        override
        onlyRole(PERMISSIONED_POOL_CONTRACT)
    {
        operatorStructById[_operatorID].nextQueuedValidatorIndex = _nextQueuedValidatorIndex;
        emit UpdatedQueuedValidatorIndex(_operatorID, _nextQueuedValidatorIndex);
    }

    /**
     * @notice update the status of a validator
     * @dev only stader network can call
     * @param _pubKey public key of the validator
     * @param _status updated status of validator
     */

    //TODO decide on role as oracle might also call it along with permissioned pool
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
        onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_rewardAddress);

        onlyOnboardedOperator(msg.sender);
        uint256 operatorId = operatorIDByAddress[msg.sender];
        operatorStructById[operatorId].operatorName = _operatorName;
        operatorStructById[operatorId].operatorRewardAddress = _rewardAddress;
        emit UpdatedOperatorDetails(msg.sender, _operatorName, _rewardAddress);
    }

    /**
     * @notice update the key deposit limit
     * @dev only admin can call
     * @param _keyDepositLimit updated key deposit limit
     */
    function updateKeyDepositLimit(uint256 _keyDepositLimit) external onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER) {
        KEY_DEPOSIT_LIMIT = _keyDepositLimit;
        emit UpdatedKeyDepositLimit(KEY_DEPOSIT_LIMIT);
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
     * @notice computes total keys for permissioned pool
     * @dev compute by looping over the total initialized, queued, active and withdrawn keys
     * @return _validatorCount total validator keys on permissioned pool
     */
    function getTotalValidatorCount() external view override returns (uint256 _validatorCount) {
        return
            this.getTotalInitializedValidatorCount() +
            this.getTotalQueuedValidatorCount() +
            this.getTotalActiveValidatorCount() +
            this.getTotalWithdrawnValidatorCount();
    }

    /**
     * @notice computes total initialized keys for permissioned pool
     * @dev compute by looping over all the initialized keys of all operators
     * @return _validatorCount initialized validator count
     */
    function getTotalInitializedValidatorCount() public view override returns (uint256 _validatorCount) {
        for (uint256 i = 1; i < nextOperatorId; i++) {
            if (operatorStructById[i].active) {
                _validatorCount += operatorStructById[i].initializedValidatorCount;
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
     * @notice computes total withdrawn keys for permissioned pool
     * @dev compute by looping over all the withdrawn keys of all operators
     * @return _validatorCount withdrawn validator count
     */
    function getTotalWithdrawnValidatorCount() public view override returns (uint256 _validatorCount) {
        for (uint256 i = 1; i < nextOperatorId; i++) {
            _validatorCount += operatorStructById[i].withdrawnValidatorCount;
        }
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add initialized, queued, active and withdrawn validator key count to get total validators keys
     * @param _operatorId operator Id
     */
    function getOperatorTotalKeys(uint256 _operatorId) external view override returns (uint256 _totalKeys) {
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        _totalKeys =
            operatorStructById[_operatorId].initializedValidatorCount +
            operatorStructById[_operatorId].queuedValidatorCount +
            operatorStructById[_operatorId].activeValidatorCount +
            operatorStructById[_operatorId].withdrawnValidatorCount;
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
        bytes calldata _pubKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        uint256 _operatorId
    ) internal {
        uint256 totalKeys = this.getOperatorTotalKeys(_operatorId);
        address withdrawVault = IVaultFactory(vaultFactoryAddress).computeWithdrawVaultAddress(
            poolId,
            _operatorId,
            totalKeys
        );
        bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVault
        );
        _validateKeys(_pubKey, withdrawCredential, _signature, _depositDataRoot);
        IVaultFactory(vaultFactoryAddress).deployWithdrawVault(poolId, _operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            _pubKey,
            _signature,
            withdrawVault,
            _operatorId
        );
        validatorIdByPubKey[_pubKey] = nextValidatorId;
        operatorStructById[_operatorId].initializedValidatorCount++;
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubKey, nextValidatorId - 1);
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorQueuedValidators[operatorId].push(_validatorId);
        operatorStructById[operatorId].initializedValidatorCount--;
        operatorStructById[operatorId].queuedValidatorCount++;
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
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        if (operatorId == 0) revert OperatorNotOnBoarded();
    }

    function onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }
}
