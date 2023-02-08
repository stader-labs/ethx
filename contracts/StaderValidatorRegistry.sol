// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderPoolHelper.sol';
import './interfaces/IStaderRewardContractFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderValidatorRegistry is IStaderValidatorRegistry, Initializable, AccessControlUpgradeable {
    IStaderPoolHelper staderPoolHelper;
    IStaderRewardContractFactory rewardContractFactory;
    IStaderOperatorRegistry staderOperatorRegistry;
    uint256 public override nextValidatorId;
    uint256 public override registeredValidatorCount;
    uint256 public constant override collateralETH = 4 ether;
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Validator {
        bool validatorDepositStatus; // state of validator
        bool isWithdrawal; //status of validator readiness to withdraw
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes withdrawalAddress; //eth1 withdrawal address for validator
        uint8 staderPoolId; // validator pool type
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }
    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorRegistryIndexByPubKey;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(address _rewardFactory, address _operatorRegistry)
        external
        initializer
        checkZeroAddress(_rewardFactory)
        checkZeroAddress(_operatorRegistry)
    {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        rewardContractFactory = IStaderRewardContractFactory(_rewardFactory);
        staderOperatorRegistry = IStaderOperatorRegistry(_operatorRegistry);
    }

    // TODO add validator keys adding function
    function addValidatorKeys(
        bytes calldata _validatorPubKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external payable override {
        (, uint8 staderPoolId, , , uint256 operatorId, , , ) = staderOperatorRegistry.operatorRegistry(msg.sender);
        //TODO call SDlocker to check enough SD
        if (operatorId == 0) revert OperatorNotOnBoarded();
        if (staderPoolId == 0 && msg.value == 4 ether) {
            _addValidatorKey(_validatorPubKey, _validatorSignature, staderPoolId, _depositDataRoot, operatorId);
            return;
        }
        if (staderPoolId == 1 && staderOperatorRegistry.isWhitelistedPermissionedNO(msg.sender)) {
            _addValidatorKey(_validatorPubKey, _validatorSignature, staderPoolId, _depositDataRoot, operatorId);
            return;
        } else {
            revert InvalidInputOfKeys();
        }
    }

    /**
     * @notice update the count of total registered validator on beacon chain
     * @dev only accept call from stader network pools
     * @param _pubKey public key of the validator
     */
    function incrementRegisteredValidatorCount(bytes memory _pubKey) external override onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
        require(index != type(uint256).max, 'pubKey does not exist on registry');
        validatorRegistry[index].validatorDepositStatus = true;
        registeredValidatorCount++;
    }

    /**
     * @notice return the index of next permission less validator available for the deposit
     * @dev return uint256 max if no permission less validator is available
     * @param _poolId stader pool Id of the validator
     * @param _inputOperatorId operatorID of a permissionLess operator
     */
    function getValidatorIndexForOperatorId(uint8 _poolId, uint256 _inputOperatorId)
        external
        view
        override
        returns (uint256)
    {
        uint256 index = 0;
        while (index < nextValidatorId) {
            if (
                //slither-disable-next-line boolean-equal
                validatorRegistry[index].validatorDepositStatus == false &&
                validatorRegistry[index].staderPoolId == _poolId &&
                validatorRegistry[index].operatorId == _inputOperatorId
            ) {
                return index;
            }
            index++;
        }
        return type(uint256).max;
    }

    /**
     * @notice fetch validator index in the registry based on public key
     * @dev return uint256 max if no index is not found
     * @param _publicKey public key of the validator
     */
    function getValidatorIndexByPublicKey(bytes memory _publicKey) public view override returns (uint256) {
        uint256 index = validatorRegistryIndexByPubKey[_publicKey];
        if (keccak256(_publicKey) == keccak256(validatorRegistry[index].pubKey)) return index;
        return type(uint256).max;
    }

    /**
     * @notice update the value of bond eth in case of permission less pool validators
     * @dev only accept call from stader slashing manager contract
     * @param _pubKey public key of the validator
     */
    function handleWithdrawnValidators(bytes memory _pubKey) external override onlyRole(STADER_SLASHING_MANAGER) {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
        require(index != type(uint256).max, 'pubKey does not exist on registry');
        _removeValidatorFromRegistry(_pubKey, index);
    }

    function increasePenaltyCount(uint256 validatorIndex) external override onlyRole(STADER_SLASHING_MANAGER) {
        validatorRegistry[validatorIndex].penaltyCount++;
    }

    function updateBondEth(uint256 validatorIndex, uint256 currentBondEth)
        external
        override
        onlyRole(STADER_SLASHING_MANAGER)
    {
        validatorRegistry[validatorIndex].bondEth = currentBondEth;
    }

    function _addValidatorKey(
        bytes calldata _pubKey,
        bytes calldata _signature,
        uint8 _poolId,
        bytes32 _depositDataRoot,
        uint256 _operatorId
    ) private {
        uint256 totalKeys = staderOperatorRegistry.getTotalValidatorKeys(msg.sender);
        address withdrawVault = rewardContractFactory.computeWithdrawVaultAddress(_operatorId, totalKeys);
        bytes memory withdrawCredential = rewardContractFactory.getValidatorWithdrawCredential(withdrawVault);
        _validateKeys(_pubKey, withdrawCredential, _signature, _depositDataRoot);
        validatorRegistry[nextValidatorId] = Validator(
            false,
            false,
            _pubKey,
            _signature,
            withdrawCredential,
            _poolId,
            _depositDataRoot,
            _operatorId,
            msg.value,
            0
        );
        staderPoolHelper.incrementQueuedValidatorKeys(_poolId);
        staderOperatorRegistry.incrementQueuedValidatorsCount(_operatorId);
        nextValidatorId++;
    }

    function markValidatorReadyForWithdrawal(uint256 validatorIndex)
        external
        override
        onlyRole(STADER_SLASHING_MANAGER)
    {
        validatorRegistry[validatorIndex].isWithdrawal = true;
    }

    function updatePoolHelper(address _staderPoolHelper)
        external
        checkZeroAddress(_staderPoolHelper)
        onlyRole(STADER_NETWORK_POOL)
    {
        staderPoolHelper = IStaderPoolHelper(_staderPoolHelper);
    }

    function _removeValidatorFromRegistry(bytes memory _pubKey, uint256 _index) internal {
        delete (validatorRegistry[_index]);
        delete (validatorRegistryIndexByPubKey[_pubKey]);
        emit RemovedValidatorFromRegistry(_pubKey);
    }

    function _validateKeys(
        bytes calldata pubkey,
        bytes memory withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) public pure {
        uint256 deposit_amount = DEPOSIT_SIZE / 1 gwei;
        bytes memory amount = to_little_endian_64(uint64(deposit_amount));
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
                sha256(abi.encodePacked(amount, bytes24(0), signature_root))
            )
        );

        // Verify computed and expected deposit data roots match
        require(
            node == deposit_data_root,
            'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
        );
    }

    function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    function getFundBack(address _add) external onlyRole(STADER_NETWORK_POOL) {
        // solhint-disable-next-line
        (bool success, ) = payable(_add).call{value: address(this).balance}('');
        if (!success) revert TransferFailed();
    }
}
