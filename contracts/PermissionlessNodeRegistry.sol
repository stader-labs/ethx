pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IStaderPoolHelper.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionlessNodeRegistry is IPermissionlessNodeRegistry, AccessControlUpgradeable, PausableUpgradeable {
    address public override poolHelper;
    address public override vaultFactory;
    address public override elRewardSocializePool;
    uint256 public override nextOperatorId;
    uint256 public override nextValidatorId;
    uint256 public override queuedValidatorsSize;
    uint256 public constant override collateralETH = 4 ether;
    uint256 public constant override DEPOSIT_SIZE = 32 ether;

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
        address _elRewardSocializePool
    ) external initializer {
        Address.checkNonZeroAddress(_vaultFactory);
        Address.checkNonZeroAddress(_elRewardSocializePool);
        __AccessControl_init_unchained();
        __Pausable_init();
        vaultFactory = _vaultFactory;
        elRewardSocializePool = _elRewardSocializePool;
        nextOperatorId = 1;
        nextValidatorId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice onboard a node operator
     * @dev any one call, check for whiteListOperator in case of permissionedPool
     * @param _optInForMevSocialize opted in or not to socialize mev and priority fee
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address
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
     * @param _validatorPubKey public key of validator
     * @param _validatorSignature signature of a validator
     * @param _depositDataRoot deposit data root of validator
     */
    function addValidatorKeys(
        bytes calldata _validatorPubKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external payable override {
        if (msg.value != collateralETH) revert InvalidBondEthValue();
        Operator storage operator = operatorRegistry[msg.sender];
        uint256 operatorId = operator.operatorId;
        //TODO call SDlocker to check enough SD
        if (operatorId == 0) revert OperatorNotOnBoarded();
        _addValidatorKey(_validatorPubKey, _validatorSignature, _depositDataRoot, operatorId);
    }

    /**
     * @notice move validator state from INITIALIZE to PRE_DEPOSIT after receiving pre-signed messages for withdrawal
     * @dev only admin can call
     * @param _pubKeys array of pubKeys ready to be moved to PRE_DEPOSIT state
     */
    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        for (uint256 i = 0; i < _pubKeys.length; i++) {
            uint256 validatorId = validatorIdByPubKey[_pubKeys[i]];
            if (validatorId == 0) revert PubKeyDoesNotExist();
            _markKeyReadyToDeposit(validatorId);
            emit ValidatorMarkedReadyToDeposit(_pubKeys[i], validatorId);
        }
    }

    /**
     * @notice removes the keys after they are deposited on beacon chain
     * @param _keyCount count of used keys from queue that we want to delete
     * @param _index starting index to delete keys
     */

    //TODO check the math of condition
    function deleteDepositedQueueValidator(uint256 _keyCount, uint256 _index)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        if (_index + _keyCount >= queuedValidatorsSize) revert InvalidIndex();
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
        operatorRegistry[_nodeOperator].withdrawnValidatorCount++;
        emit IncrementedWithdrawnValidatorsCount(
            operatorRegistry[_nodeOperator].operatorId,
            operatorRegistry[_nodeOperator].withdrawnValidatorCount
        );
    }

    function getOperatorCount() public view override returns (uint256 _operatorCount) {
        _operatorCount = nextOperatorId - 1;
    }

    /**
     * @notice get the total deposited keys for an operator
     * @dev add queued, active and withdrawn validator to get total validators keys
     * @param _nodeOperator owner of operator
     */
    function getTotalValidatorKeys(address _nodeOperator) public view override returns (uint256 _totalKeys) {
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
    function transferCollateralToPool(uint256 _amount) external override onlyRole(STADER_NETWORK_POOL) {
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
     * @param _staderPoolHelper address of poolHelper
     */
    function updatePoolHelper(address _staderPoolHelper)
        external
        override
        onlyRole(PERMISSIONLESS_NODE_REGISTRY_OWNER)
    {
        Address.checkNonZeroAddress(_staderPoolHelper);
        poolHelper = _staderPoolHelper;
        emit UpdatedPoolHelper(_staderPoolHelper);
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
        IStaderPoolHelper(poolHelper).incrementInitializedValidatorKeys(1);
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
        IStaderPoolHelper(poolHelper).reduceInitializedValidatorKeys(1);
        IStaderPoolHelper(poolHelper).incrementQueuedValidatorKeys(1);
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

        (, , address poolAddress, , , , , , ) = IStaderPoolHelper(poolHelper).staderPool(1);

        // solhint-disable-next-line
        (bool success, ) = payable(poolAddress).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }

    function onlyValidName(string calldata _name) internal {
        if (bytes(_name).length == 0) revert EmptyNameString();
        if (bytes(_name).length > OPERATOR_MAX_NAME_LENGTH) revert NameCrossedMaxLength();
    }
}
