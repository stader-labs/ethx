// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolFactory.sol';
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
    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    address public override poolFactoryAddress;
    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override maxKeyPerOperator;
    uint256 public override BATCH_KEY_DEPOSIT_LIMIT;
    uint256 public override operatorIdForExcessDeposit;
    uint256 public override totalActiveValidatorCount;
    uint256 public override totalActiveOperatorCount;

    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;
    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');
    bytes32 public constant override VALIDATOR_STATUS_ROLE = keccak256('VALIDATOR_STATUS_ROLE');
    bytes32 public constant override STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant override PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');
    bytes32 public constant override PERMISSIONED_NODE_REGISTRY_OWNER = keccak256('PERMISSIONED_NODE_REGISTRY_OWNER');

    // mapping of validator ID and Validator struct
    mapping(uint256 => Validator) public override validatorRegistry;
    // mapping of bytes public key and validator Id
    mapping(bytes => uint256) public override validatorIdByPubkey;
    // mapping of operaot ID and Operator struct
    mapping(uint256 => Operator) public override operatorStructById;
    // mapping of operator address and operator Id
    mapping(address => uint256) public override operatorIDByAddress;
    // mapping of whitelisted permissioned node operator
    mapping(address => bool) public override permissionList;
    //mapping of operator wise queued validator IDs arrays
    mapping(uint256 => uint256[]) public override validatorIdsByOperatorId;
    //mapping of operator ID and nextQueuedValidatorIndex
    mapping(uint256 => uint256) public override nextQueuedValidatorIndexByOperatorId;
    mapping(uint256 => uint256) public socializingPoolStateChangeTimestamp;

    function initialize(
        address _adminOwner,
        address _sdCollateral,
        address _vaultFactoryAddress,
        address _elRewardSocializePool,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_sdCollateral);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        __AccessControl_init_unchained();
        __Pausable_init();
        sdCollateral = _sdCollateral;
        vaultFactoryAddress = _vaultFactoryAddress;
        elRewardSocializePool = _elRewardSocializePool;
        poolFactoryAddress = _poolFactoryAddress;
        nextOperatorId = 1;
        nextValidatorId = 1;
        operatorIdForExcessDeposit = 1;
        BATCH_KEY_DEPOSIT_LIMIT = 100;
        maxKeyPerOperator = 1000;
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
     * @dev only accepts node operator onboarded along with sufficient SD lockup
     * @param _pubkey public key of validators
     * @param _signature signature of a validators for deposit
     */
    function addValidatorKeys(bytes[] calldata _pubkey, bytes[] calldata _signature) external override whenNotPaused {
        if (_pubkey.length != _signature.length) revert InvalidSizeOfInputKeys();

        uint256 keyCount = _pubkey.length;
        if (keyCount == 0 || keyCount > BATCH_KEY_DEPOSIT_LIMIT) revert InvalidCountOfKeys();

        uint256 operatorId = _onlyActiveOperator(msg.sender);

        uint256 operatorTotalKeyCount = this.getOperatorTotalKeys(operatorId);
        uint256 totalNonWithdrawnKeys = this.getOperatorTotalNonWithdrawnKeys(msg.sender, 0, operatorTotalKeyCount);
        if ((totalNonWithdrawnKeys + keyCount) > maxKeyPerOperator) revert maxKeyLimitReached();
        address payable operatorRewardAddress = this.getOperatorRewardAddress(operatorId);

        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughSDCollateral(msg.sender, poolId, totalNonWithdrawnKeys + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_pubkey[i], _signature[i], operatorId, operatorRewardAddress);
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

        uint256 validatorPerOperator = numValidators / totalActiveOperatorCount;
        uint256[] memory remainingOperatorCapacity = new uint256[](nextOperatorId);
        uint256 totalValidatorToDeposit;

        if (validatorPerOperator != 0) {
            for (uint256 i = 1; i < nextOperatorId; i++) {
                if (!operatorStructById[i].active) continue;
                remainingOperatorCapacity[i] = _getOperatorQueuedValidatorCount(i);
                selectedOperatorCapacity[i] = Math.min(remainingOperatorCapacity[i], validatorPerOperator);
                totalValidatorToDeposit += selectedOperatorCapacity[i];
                remainingOperatorCapacity[i] -= selectedOperatorCapacity[i];
            }
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
     * @notice handles the front run validators
     * @dev only permissioned pool can call,
     * reduce the total active validator count by length of input pubkey
     */
    function reportFrontRunValidator(bytes[] calldata _pubkeys) external override onlyRole(PERMISSIONED_POOL) {
        uint256 pubkeyLength = _pubkeys.length;
        for (uint256 i = 0; i < pubkeyLength; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            _handleFrontRun(validatorId);
            emit ValidatorMarkedAsFrontRunned(_pubkeys[i], validatorId);
        }
        _decreaseTotalActiveValidatorCount(pubkeyLength);
    }

    /**
     * @notice handle the invalid signature validators
     * @dev only permissioned pool can call, mark validator status as `INVALID_SIGNATURE`
     */
    function reportInvalidSignatureValidator(bytes[] calldata _pubkeys) external override onlyRole(PERMISSIONED_POOL) {
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            validatorRegistry[validatorId].status = ValidatorStatus.INVALID_SIGNATURE;
            emit ValidatorStatusMarkedAsInvalidSignature(_pubkeys[i], validatorId);
        }
    }

    /**
     * @notice handling of fully withdrawn validators
     * @dev list of pubkeys reported by oracle, settle all EL and CL vault balances
     * @param  _pubkeys array of withdrawn validator's pubkey
     */
    function withdrawnValidators(bytes[] calldata _pubkeys) external onlyRole(STADER_ORACLE) {
        uint256 withdrawnValidatorCount = _pubkeys.length;
        for (uint256 i = 0; i < withdrawnValidatorCount; i++) {
            uint256 validatorId = validatorIdByPubkey[_pubkeys[i]];
            if (validatorId == 0) revert PubkeyDoesNotExist();
            validatorRegistry[validatorId].status = ValidatorStatus.WITHDRAWN;
            //take out money from withdraw vault --need interface of withdrawVault
            //if optout, clear nodeELVault --need interfaces of NodeELVault
            emit ValidatorWithdrawn(_pubkeys[i], validatorId);
        }
        _decreaseTotalActiveValidatorCount(withdrawnValidatorCount);
    }

    /**
     * @notice deactivate a node operator from running new validator clients
     * @dev only accept call from address having `OPERATOR_STATUS_ROLE` role
     * @param _operatorID ID of the operator to deactivate
     */
    function deactivateNodeOperator(uint256 _operatorID) external override onlyRole(STADER_MANAGER_BOT) {
        operatorStructById[_operatorID].active = false;
        totalActiveOperatorCount--;
    }

    /**
     * @notice activate a node operator for running new validator clients
     * @dev only accept call from address having `OPERATOR_STATUS_ROLE` role
     * @param _operatorID ID of the operator to activate
     */
    function activateNodeOperator(uint256 _operatorID) external override onlyRole(STADER_MANAGER_BOT) {
        operatorStructById[_operatorID].active = true;
        totalActiveOperatorCount++;
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
        nextQueuedValidatorIndexByOperatorId[_operatorID] = _nextQueuedValidatorIndex;
        emit UpdatedQueuedValidatorIndex(_operatorID, _nextQueuedValidatorIndex);
    }

    /**
     * @notice update the status of a validator
     * @dev only `VALIDATOR_STATUS_ROLE` role can call
     * @param _pubkey public key of the validator
     * @param _status updated status of validator
     */

    function updateValidatorStatus(bytes calldata _pubkey, ValidatorStatus _status)
        external
        override
        onlyRole(VALIDATOR_STATUS_ROLE)
    {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        validatorRegistry[validatorId].status = _status;
        emit UpdatedValidatorStatus(_pubkey, _status);
    }

    /**
     * @notice update the address of sd collateral contract
     * @dev only admin can call
     * @param _sdCollateral address of SD collateral contract
     */
    function updateSDCollateralAddress(address _sdCollateral)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_sdCollateral);
        sdCollateral = _sdCollateral;
        emit UpdatedSDCollateralAddress(_sdCollateral);
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
     * @notice update the address permissioned socialize pool
     * @dev only admin can call
     * @param _elRewardSocializePool address of permissioned EL reward socialize pool
     */
    function updateELRewardSocializePool(address _elRewardSocializePool)
        external
        override
        onlyRole(PERMISSIONED_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_elRewardSocializePool);
        elRewardSocializePool = _elRewardSocializePool;
        emit UpdatedELRewardSocializePool(_elRewardSocializePool);
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
        _onlyActiveOperator(msg.sender);
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

    // @inheritdoc INodeRegistry
    function getSocializingPoolStateChangeTimestamp(uint256 _operatorId) external view returns (uint256) {
        return socializingPoolStateChangeTimestamp[_operatorId];
    }

    // @inheritdoc INodeRegistry
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        uint256 validatorId = validatorIdByPubkey[_pubkey];
        if (validatorId == 0) {
            Operator memory emptyOperator;

            return emptyOperator;
        }

        uint256 operatorId = validatorRegistry[validatorId].operatorId;
        return operatorStructById[operatorId];
    }

    /**
     * @notice increase the total active validator count
     * @dev only permissioned pool calls it when it does the deposit of 1 ETH for validator
     * @param _count count to increase total active validator value
     */
    function increaseTotalActiveValidatorCount(uint256 _count) external override onlyRole(PERMISSIONED_POOL) {
        totalActiveValidatorCount += _count;
    }

    // /**
    //  * @notice returns the total active operator count
    //  */
    // function getTotalActiveOperatorCount() external view override returns (uint256 _activeOperatorCount) {
    //     for (uint256 i = 1; i < nextOperatorId; i++) {
    //         if (operatorStructById[i].active) {
    //             _activeOperatorCount++;
    //         }
    //     }
    // }

    /**
     * @notice computes total queued keys for permissioned pool
     * @dev compute by looping over operators queued keys count
     * @return _validatorCount queued validator count
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        uint256 totalQueuedValidators;
        for (uint256 i = 1; i < nextOperatorId; i++) {
            if (operatorStructById[i].active) {
                totalQueuedValidators += _getOperatorQueuedValidatorCount(i);
            }
        }
        return totalQueuedValidators;
    }

    /**
     * @notice returns total active keys for permissioned pool
     * @dev return the variable totalActiveValidatorCount
     * @return _validatorCount active validator count
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return totalActiveValidatorCount;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev length of the validatorIds array for an operator
     * @param _operatorId ID of node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) external view override returns (uint256 _totalKeys) {
        _totalKeys = validatorIdsByOperatorId[_operatorId].length;
    }

    /**
     * @notice get the total non withdrawn keys for an operator
     * @dev loop over all keys of an operator from start index till
     *  end index (exclusive) to get the count excluding the withdrawn keys
     * @param _nodeOperator address of node operator
     */
    function getOperatorTotalNonWithdrawnKeys(
        address _nodeOperator,
        uint256 startIndex,
        uint256 endIndex
    ) external view override returns (uint256) {
        if (startIndex > endIndex) {
            revert InvalidStartAndEndIndex();
        }
        uint256 operatorId = operatorIDByAddress[_nodeOperator];
        uint256 validatorCount = this.getOperatorTotalKeys(operatorId);
        endIndex = endIndex > validatorCount ? validatorCount : endIndex;
        uint256 totalNonWithdrawnKeyCount;
        for (uint256 i = startIndex; i < endIndex; i++) {
            uint256 validatorId = validatorIdsByOperatorId[operatorId][i];
            if (_isWithdrawnValidator(validatorId)) continue;
            totalNonWithdrawnKeyCount++;
        }
        return totalNonWithdrawnKeyCount;
    }

    function getCollateralETH() external pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice returns the operator reward address
     * @param _operatorId operator ID
     */
    function getOperatorRewardAddress(uint256 _operatorId) external view override returns (address payable) {
        return operatorStructById[_operatorId].operatorRewardAddress;
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

    /**
     * @notice returns the validator for which protocol don't have money on execution layer
     * @dev loop over all validator to filter out the initialized, front run and withdrawn and return the rest
     */
    function getAllActiveValidators() public view override returns (Validator[] memory) {
        Validator[] memory validators = new Validator[](this.getTotalActiveValidatorCount());
        uint256 validatorCount = 0;
        for (uint256 i = 1; i < nextValidatorId; i++) {
            if (_isActiveValidator(i)) {
                validators[validatorCount] = validatorRegistry[i];
                validatorCount++;
            }
        }
        return validators;
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return validatorRegistry[validatorIdByPubkey[_pubkey]];
    }

    function getValidator(uint256 _validatorId) external view returns (Validator memory) {
        return validatorRegistry[_validatorId];
    }

    // check for duplicate keys in permissioned node registry
    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        if (validatorIdByPubkey[_pubkey] != 0) return true;
        return false;
    }

    function _onboardOperator(string calldata _operatorName, address payable _operatorRewardAddress) internal {
        operatorStructById[nextOperatorId] = Operator(true, true, _operatorName, _operatorRewardAddress, msg.sender);
        operatorIDByAddress[msg.sender] = nextOperatorId;
        socializingPoolStateChangeTimestamp[nextOperatorId] = block.timestamp;
        nextOperatorId++;
        totalActiveOperatorCount++;
        emit OnboardedOperator(msg.sender, nextOperatorId - 1);
    }

    function _addValidatorKey(
        bytes calldata _pubkey,
        bytes calldata _signature,
        uint256 _operatorId,
        address payable operatorRewardAddress
    ) internal {
        _validateKeys(_pubkey, _signature);
        uint256 totalKeys = this.getOperatorTotalKeys(_operatorId);

        address withdrawVault = IVaultFactory(vaultFactoryAddress).deployWithdrawVault(
            poolId,
            _operatorId,
            totalKeys,
            operatorRewardAddress
        );
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            _pubkey,
            _signature,
            withdrawVault,
            _operatorId,
            0
        );
        validatorIdByPubkey[_pubkey] = nextValidatorId;
        validatorIdsByOperatorId[_operatorId].push(nextValidatorId);
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubkey, nextValidatorId - 1);
    }

    // handle front run validator by changing their status and deactivating operator
    function _handleFrontRun(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.FRONT_RUN;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        operatorStructById[operatorId].active = false;
    }

    // returns operator total queued validator count, internal use
    function _getOperatorQueuedValidatorCount(uint256 _operatorId) internal view returns (uint256 _validatorCount) {
        _validatorCount =
            validatorIdsByOperatorId[_operatorId].length -
            nextQueuedValidatorIndexByOperatorId[_operatorId];
    }

    // checks for keys lengths, and if pubkey is already there
    function _validateKeys(bytes calldata _pubkey, bytes calldata _signature) private view {
        if (_pubkey.length != PUBKEY_LENGTH) revert InvalidLengthOfpubkey();
        if (_signature.length != SIGNATURE_LENGTH) revert InvalidLengthOfSignature();
        if (IPoolFactory(poolFactoryAddress).isExistingPubkey(_pubkey)) revert PubkeyAlreadyExist();
    }

    // operator in active state
    function _onlyActiveOperator(address _operAddr) internal view returns (uint256 _operatorId) {
        _operatorId = operatorIDByAddress[_operAddr];
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        if (!operatorStructById[_operatorId].active) revert OperatorIsDeactivate();
    }

    // checks if validator is active, active validator are those having user share on beacon chain
    function _isActiveValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        if (
            validator.status == ValidatorStatus.INITIALIZED ||
            validator.status == ValidatorStatus.INVALID_SIGNATURE ||
            validator.status == ValidatorStatus.FRONT_RUN ||
            validator.status == ValidatorStatus.WITHDRAWN
        ) return false;
        return true;
    }

    // checks if validator is withdrawn
    function _isWithdrawnValidator(uint256 _validatorId) internal view returns (bool) {
        Validator memory validator = validatorRegistry[_validatorId];
        if (validator.status == ValidatorStatus.WITHDRAWN) return true;
        return false;
    }

    // only valid name with string length limit
    function _onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }

    // decreases the pool total active validator count
    function _decreaseTotalActiveValidatorCount(uint256 _count) internal {
        totalActiveValidatorCount -= _count;
    }
}
