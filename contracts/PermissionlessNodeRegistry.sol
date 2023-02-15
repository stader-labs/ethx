pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionlessNodeRegistry is
    INodeRegistry,
    IPermissionlessNodeRegistry,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint256 public initializedValidatorCount;
    uint256 public queuedValidatorCount;
    uint256 public activeValidatorCount;
    uint256 public withdrawnValidatorCount;

    address public override poolHelper;
    address public poolFactoryAddress;
    address public override vaultFactory;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override queuedValidatorsSize;
    uint256 public constant override collateralETH = 4 ether;

    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;
    uint256 public constant override OPERATOR_MAX_NAME_LENGTH = 255;

    bytes32 public constant override PERMISSIONLESS_NODE_REGISTRY_OWNER =
        keccak256('PERMISSIONLESS_NODE_REGISTRY_OWNER');
    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');

    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorIdByPubKey;
    mapping(uint256 => uint256) public override queueToDeposit;

    mapping(address => Operator) public override operatorRegistry;
    mapping(uint256 => address) public override operatorByOperatorId;

    struct Validator {
        ValidatorStatus status; // state of validator
        bool isWithdrawal; //status of validator readiness to withdraw
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes withdrawalAddress; //eth1 withdrawal address for validator
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }

    struct Operator {
        bool optedForSocializingPool; // operator opted for socializing pool
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        uint256 operatorId; //pool wise unique ID given by stader network
        uint256 initializedValidatorCount; //validator whose keys added but not given pre signed msg for withdrawal
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _vaultFactory,
        address _elRewardSocializePool,
        address _poolFactoryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_vaultFactory);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        Address.checkNonZeroAddress(_poolFactoryAddress);
        __AccessControl_init_unchained();
        __Pausable_init();
        vaultFactory = _vaultFactory;
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
        if (operatorRegistry[msg.sender].operatorId != 0) revert OperatorAlreadyOnBoarded();
        mevFeeRecipientAddress = elRewardSocializePool;
        if (!_optInForMevSocialize) {
            mevFeeRecipientAddress = IVaultFactory(vaultFactory).deployNodeELRewardVault(
                1,
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
        if (_validatorPubKey.length != _validatorSignature.length || _validatorPubKey.length != _depositDataRoot.length)
            revert InvalidSizeOfInputKeys();
        uint256 keyCount = _validatorPubKey.length;
        if (keyCount == 0) revert NoKeysProvided();
        if (msg.value != keyCount * collateralETH) revert InvalidBondEthValue();
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
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
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
        if (_index + _keyCount > queuedValidatorsSize) revert InvalidIndex();
        for (uint256 i = _index; i < _index + _keyCount; i++) {
            if (validatorRegistry[queueToDeposit[_index]].status == ValidatorStatus.PRE_DEPOSIT)
                revert ValidatorInPreDepositState();
            delete (queueToDeposit[_index]);
        }
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _nodeOperator operator ID
     */
    function reduceQueuedValidatorsCount(address _nodeOperator) external override onlyRole(STADER_NETWORK_POOL) {
        onlyOnboardedOperator(_nodeOperator);
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
        onlyOnboardedOperator(_nodeOperator);
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
        onlyOnboardedOperator(_nodeOperator);

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
        onlyOnboardedOperator(_nodeOperator);
        operatorRegistry[_nodeOperator].withdrawnValidatorCount++;
        emit IncrementedWithdrawnValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].withdrawnValidatorCount
        );
    }

    /**
     * @notice returns the total operator count
     */
    function getOperatorCount() public view override returns (uint256 _operatorCount) {
        _operatorCount = nextOperatorId - 1;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add queued, active and withdrawn validator to get total validators keys
     * @param _nodeOperator owner of operator
     */
    function getTotalValidatorKeys(address _nodeOperator) public view override returns (uint256 _totalKeys) {
        onlyOnboardedOperator(_nodeOperator);
        _totalKeys =
            operatorRegistry[_nodeOperator].initializedValidatorCount +
            operatorRegistry[_nodeOperator].queuedValidatorCount +
            operatorRegistry[_nodeOperator].activeValidatorCount +
            operatorRegistry[_nodeOperator].withdrawnValidatorCount;
    }

    /**
     * @notice transfer the `_amount` to permissionless pool
     * @dev only permissionless pool can call
     * @param _amount amount of eth to send to permissionless pool
     */
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
     * @notice updates the address of pool helper
     * @dev only NOs registry can call
     * @param _staderPoolSelector address of poolHelper
     */
    function updatePoolSelector(address _staderPoolSelector)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
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
    function updateVaultAddress(address _vaultFactory) external override onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER) {
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

    function _onboardOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) internal {
        operatorRegistry[msg.sender] = Operator(
            _optInForMevSocialize,
            _operatorName,
            _operatorRewardAddress,
            nextOperatorId,
            0,
            0,
            0,
            0
        );
        operatorByOperatorId[nextOperatorId] = msg.sender;
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
        address withdrawVault = IVaultFactory(vaultFactory).computeWithdrawVaultAddress(1, _operatorId, totalKeys);
        bytes memory withdrawCredential = IVaultFactory(vaultFactory).getValidatorWithdrawCredential(withdrawVault);
        _validateKeys(_pubKey, withdrawCredential, _signature, _depositDataRoot);
        IVaultFactory(vaultFactory).deployWithdrawVault(1, _operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            false,
            _pubKey,
            _signature,
            withdrawCredential,
            _operatorId,
            msg.value,
            0
        );
        validatorIdByPubKey[_pubKey] = nextValidatorId;
        operatorRegistry[msg.sender].initializedValidatorCount++;
        emit AddedKeys(msg.sender, _pubKey, nextValidatorId);
        nextValidatorId++;
    }

    function _markKeyReadyToDeposit(uint256 _validatorId) internal {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queueToDeposit[queuedValidatorsSize] = _validatorId;
        address nodeOperator = operatorByOperatorId[validatorRegistry[_validatorId].operatorId];
        operatorRegistry[nodeOperator].initializedValidatorCount--;
        operatorRegistry[nodeOperator].queuedValidatorCount++;
        queuedValidatorsSize++;
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

        (, address poolAddress) = IPoolFactory(poolFactoryAddress).pools(1);

        // solhint-disable-next-line
        (bool success, ) = payable(poolAddress).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }

    function onlyOnboardedOperator(address _nodeOperator) internal view {
        if (operatorRegistry[_nodeOperator].operatorId == 0) revert OperatorNotOnBoarded();
    }

    function onlyValidName(string calldata _name) internal pure {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }
}
