pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionlessNodeRegistry is
    INodeRegistry,
    IPermissionlessNodeRegistry,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint8 public constant override poolId = 1;
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;

    address public poolFactoryAddress;
    address public override vaultFactoryAddress;
    address public override sdCollateral;
    address public override elRewardSocializePool;

    uint256 public totalInitializedValidatorCount;
    uint256 public totalQueuedValidatorCount;
    uint256 public totalActiveValidatorCount;
    uint256 public totalWithdrawnValidatorCount;

    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override validatorQueueSize;
    uint256 public override nextQueuedValidatorIndex;
    uint256 public constant override collateralETH = 4 ether;

    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override PERMISSIONLESS_POOL = keccak256('PERMISSIONLESS_POOL');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    bytes32 public constant override STADER_MANAGER_BOT = keccak256('STADER_MANAGER_BOT');

    bytes32 public constant override PERMISSIONLESS_NODE_REGISTRY_OWNER =
        keccak256('PERMISSIONLESS_NODE_REGISTRY_OWNER');

    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorIdByPubKey;
    mapping(uint256 => uint256) public override queuedValidators;

    mapping(uint256 => Operator) public override operatorStructById;
    mapping(address => uint256) public override operatorIDByAddress;

    struct Validator {
        ValidatorStatus status; // state of validator
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        address withdrawVaultAddress; //eth1 withdrawal address for validator
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }

    struct Operator {
        bool optedForSocializingPool; // operator opted for socializing pool
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        address operatorAddress; //address of operator to interact with stader
        uint256 totalKeys; //total keys added by a permissionless Node Operator
        uint256 withdrawnKeys; //count of withdrawn keys
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _vaultFactoryAddress,
        address _elRewardSocializePool,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        __AccessControl_init_unchained();
        __Pausable_init();
        vaultFactoryAddress = _vaultFactoryAddress;
        elRewardSocializePool = _elRewardSocializePool;
        poolFactoryAddress = _poolFactoryAddress;
        nextOperatorId = 1;
        nextValidatorId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, permissionless
     * @param _optInForMevSocialize opted in or not to socialize mev and priority fee
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address for all validator clients
     */
    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external override whenNotPaused returns (address mevFeeRecipientAddress) {
        onlyValidName(_operatorName);
        Address.checkNonZeroAddress(_operatorRewardAddress);

        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (operatorId != 0) revert OperatorAlreadyOnBoarded();

        mevFeeRecipientAddress = elRewardSocializePool;
        if (!_optInForMevSocialize) {
            mevFeeRecipientAddress = IVaultFactory(vaultFactoryAddress).deployNodeELRewardVault(
                poolId,
                nextOperatorId,
                payable(_operatorRewardAddress)
            );
        }
        _onboardOperator(_optInForMevSocialize, _operatorName, _operatorRewardAddress);
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
        onlyOnboardedOperator(msg.sender);
        if (_validatorPubKey.length != _validatorSignature.length || _validatorPubKey.length != _depositDataRoot.length)
            revert InvalidSizeOfInputKeys();

        uint256 keyCount = _validatorPubKey.length;
        if (keyCount == 0) revert NoKeysProvided();

        uint256 operatorId = operatorIDByAddress[msg.sender];
        if (msg.value != keyCount * collateralETH) revert InvalidBondEthValue();

        uint256 totalKeysExceptWithdrawn = operatorStructById[operatorId].totalKeys -
            operatorStructById[operatorId].withdrawnKeys;

        //check if operator has enough SD collateral for adding `keyCount` keys
        ISDCollateral(sdCollateral).hasEnoughXSDCollateral(msg.sender, poolId, totalKeysExceptWithdrawn + keyCount);

        for (uint256 i = 0; i < keyCount; i++) {
            _addValidatorKey(_validatorPubKey[i], _validatorSignature[i], _depositDataRoot[i], operatorId);
        }
        operatorStructById[operatorId].totalKeys += keyCount;
        totalInitializedValidatorCount += keyCount;
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
        onlyRole(STADER_MANAGER_BOT)
    {
        for (uint256 i = 0; i < _pubKeys.length; i++) {
            uint256 validatorId = validatorIdByPubKey[_pubKeys[i]];
            if (validatorId == 0) revert PubKeyDoesNotExist();
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubKeys[i], validatorId);
        }

        totalInitializedValidatorCount -= _pubKeys.length;
        totalQueuedValidatorCount += _pubKeys.length;
    }

    /**
     * @notice deletes the queued keys which are deposited to reduce the space
     * @dev only admin can call, will revert if any key is not deposited
     * @param _keyCount count of keys to delete
     * @param _index starting index of queue to delete keys
     */
    function deleteDepositedQueueValidator(uint256 _keyCount, uint256 _index)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        if (_index + _keyCount > validatorQueueSize) revert InvalidIndex();
        for (uint256 i = _index; i < _index + _keyCount; i++) {
            if (validatorRegistry[queuedValidators[_index]].status == ValidatorStatus.PRE_DEPOSIT)
                revert ValidatorInPreDepositState();
            delete (queuedValidators[_index]);
        }
    }

    /**
     * @notice reduce the pool total queued validator count
     * @dev only accept call from stader network contract
     * @param _count count of keys to reduce from `totalQueuedValidatorCount`
     */
    function reduceTotalQueuedValidatorsCount(uint256 _count) external override onlyRole(PERMISSIONLESS_POOL) {
        totalQueuedValidatorCount -= _count;
    }

    /**
     * @notice increase the pool total active validator count
     * @dev only accept call from stader network contract
     * @param _count count of keys to increase value of `totalActiveValidatorCount`
     */
    function increaseTotalActiveValidatorsCount(uint256 _count) external override onlyRole(PERMISSIONLESS_POOL) {
        totalActiveValidatorCount += _count;
    }

    /**
     * @notice reduce the pool total active validator count
     * @dev only accept call from stader network contract
     * @param _count count of keys to reduce from `totalActiveValidatorCount`
     */
    function reduceTotalActiveValidatorsCount(uint256 _count) external override onlyRole(PERMISSIONLESS_POOL) {
        totalActiveValidatorCount -= _count;
    }

    /**
     * @notice increase the withdrawn keys count of node operator and update totalWithdrawn keys
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID of the node
     * @param _count count of keys to increase value of operator withdrawn keys and `totalWithdrawnValidatorCount`
     */
    //TODO decide on the role
    function increaseTotalWithdrawValidatorsCount(uint256 _operatorId, uint256 _count)
        external
        override
        onlyRole(STADER_NETWORK_POOL)
    {
        operatorStructById[_operatorId].withdrawnKeys += _count;
        totalWithdrawnValidatorCount += _count;
    }

    /**
     * @notice update the next queued validator index by a count
     * @dev accept call from permissionless pool
     * @param _count count of validators picked from queue, nextIndex after `_count`
     */
    function updateNextQueuedValidatorIndex(uint256 _count) external onlyRole(PERMISSIONLESS_POOL) {
        nextQueuedValidatorIndex += _count;
        emit UpdatedNextQueuedValidatorIndex(nextQueuedValidatorIndex);
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add queued, active and withdrawn validator to get total validators keys
     * @param _operatorId operator ID of the node operator
     */
    function getOperatorTotalKeys(uint256 _operatorId) external view override returns (uint256 _totalKeys) {
        if (_operatorId == 0) revert OperatorNotOnBoarded();
        _totalKeys = operatorStructById[_operatorId].totalKeys;
    }

    /**
     * @notice transfer the `_amount` to permissionless pool
     * @dev only permissionless pool can call
     * @param _amount amount of eth to send to permissionless pool
     */
    //TODO decide on the role name
    function transferCollateralToPool(uint256 _amount) external override whenNotPaused onlyRole(STADER_NETWORK_POOL) {
        _sendValue(_amount);
    }

    /**
     * @notice update the status of a validator
     * @dev only oracle can call
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
    }

    /**
     * @notice updates the address of pool factory
     * @dev only NOs registry can call
     * @param _poolFactoryAddress address of pool factory
     */
    function updatePoolFactoryAddress(address _poolFactoryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_poolFactoryAddress);
        poolFactoryAddress = _poolFactoryAddress;
        emit UpdatedPoolFactoryAddress(poolFactoryAddress);
    }

    /**
     * @notice update the address of vault factory
     * @dev only admin can call
     * @param _vaultFactoryAddress address of vault factory
     */
    function updateVaultFactoryAddress(address _vaultFactoryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
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
     * @notice computes total keys for permissionless pool
     * @dev compute by looping over the total initialized, queued, active and withdrawn keys
     * @return _validatorCount total validator keys on permissionless pool
     */
    function getTotalValidatorCount() public view override returns (uint256 _validatorCount) {
        return
            this.getTotalInitializedValidatorCount() +
            this.getTotalQueuedValidatorCount() +
            this.getTotalActiveValidatorCount() +
            this.getTotalWithdrawnValidatorCount();
    }

    /**
     * @notice return total initialized keys for permissionless pool
     * @return _validatorCount total initialized validator count
     */
    function getTotalInitializedValidatorCount() public view override returns (uint256 _validatorCount) {
        return totalInitializedValidatorCount;
    }

    /**
     * @notice return total queued keys for permissionless pool
     * @return _validatorCount total queued validator count
     */
    function getTotalQueuedValidatorCount() public view override returns (uint256 _validatorCount) {
        return totalQueuedValidatorCount;
    }

    /**
     * @notice return total active keys for permissionless pool
     * @return _validatorCount total active validator count
     */
    function getTotalActiveValidatorCount() public view override returns (uint256 _validatorCount) {
        return totalActiveValidatorCount;
    }

    /**
     * @notice return total withdrawn keys for permissionless pool
     * @return _validatorCount total withdrawn validator count
     */
    function getTotalWithdrawnValidatorCount() public view override returns (uint256 _validatorCount) {
        return totalWithdrawnValidatorCount;
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external override onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external override onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER) {
        _unpause();
    }

    function _onboardOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) internal {
        operatorStructById[nextOperatorId] = Operator(
            _optInForMevSocialize,
            _operatorName,
            _operatorRewardAddress,
            msg.sender,
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
            _operatorId,
            msg.value,
            0
        );
        validatorIdByPubKey[_pubKey] = nextValidatorId;
        nextValidatorId++;
        emit AddedKeys(msg.sender, _pubKey, nextValidatorId - 1);
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queuedValidators[validatorQueueSize] = _validatorId;
        uint256 operatorId = validatorRegistry[_validatorId].operatorId;
        validatorQueueSize++;
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

    function _sendValue(uint256 _amount) internal {
        if (address(this).balance < _amount) revert InSufficientBalance();

        (, address poolAddress) = IPoolFactory(poolFactoryAddress).pools(poolId);

        // solhint-disable-next-line
        (bool success, ) = payable(poolAddress).call{value: _amount}('');
        if (!success) revert TransferFailed();
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
