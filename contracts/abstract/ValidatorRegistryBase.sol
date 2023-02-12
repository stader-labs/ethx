// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';
import '../interfaces/IStaderPoolHelper.sol';
import '../interfaces/IStaderValidatorRegistry.sol';
import '../interfaces/IStaderOperatorRegistry.sol';
import '../interfaces/IVaultFactory.sol';

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract ValidatorRegistryBase is Initializable, ContextUpgradeable {

    error InvalidIndex();
    error TransferFailed();
    error PubKeyDoesNotExist();
    error OperatorNotOnBoarded();
    error InvalidBondEthValue();
    error OperatorNotWhitelisted();
    error InSufficientBalance();

    event AddedToValidatorRegistry(bytes publicKey, bytes32 poolType, uint256 count);

    event RemovedValidatorFromRegistry(bytes publicKey);

    IStaderPoolHelper public poolHelper;
    IVaultFactory public vaultFactory;
    IStaderOperatorRegistry public staderOperatorRegistry;
    uint256 public  nextValidatorId;
    uint256 public  queuedValidatorIndex;
    uint256 public constant collateralETH = 4 ether;
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    bytes32 public constant VALIDATOR_REGISTRY_ADMIN = keccak256('VALIDATOR_REGISTRY_ADMIN');
    bytes32 public constant  STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant  STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Validator {
        ValidatorStatus status; // state of validator
        bool isWithdrawal; //status of validator readiness to withdraw
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes withdrawalAddress; //eth1 withdrawal address for validator
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }
    
    mapping(uint256 => Validator) public  validatorRegistry;
    // mapping() public 
    mapping(bytes => uint256) public  validatorIdByPubKey;

    mapping(uint256 => uint256) public queueToDeposit;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function __ValidatorRegistryBase_init_(address _vaultFactory, address _operatorRegistry) internal onlyInitializing 
    {
        nextValidatorId = 1;
        vaultFactory = IVaultFactory(_vaultFactory);
        staderOperatorRegistry = IStaderOperatorRegistry(_operatorRegistry);
    }

    function _markKeyReadyToDeposit(uint8 _poolId, uint256 _validatorId) internal virtual {
        validatorRegistry[_validatorId].status = ValidatorStatus.PRE_DEPOSIT;
        queueToDeposit[queuedValidatorIndex] = _validatorId;
        address nodeOperator = staderOperatorRegistry.operatorByOperatorId(validatorRegistry[_validatorId].operatorId);
        poolHelper.reduceInitializedValidatorKeys(_poolId);
        poolHelper.incrementQueuedValidatorKeys(_poolId);
        staderOperatorRegistry.reduceInitializedValidatorsCount(nodeOperator);
        staderOperatorRegistry.incrementQueuedValidatorsCount(nodeOperator);
        queuedValidatorIndex++;
    }

    function _addValidatorKey(
        bytes calldata _pubKey,
        bytes calldata _signature,
        uint8 _poolId,
        bytes32 _depositDataRoot,
        uint256 _operatorId
    ) internal virtual {
        uint256 totalKeys = staderOperatorRegistry.getTotalValidatorKeys(msg.sender);
        address withdrawVault = vaultFactory.computeWithdrawVaultAddress(_poolId,_operatorId, totalKeys);
        bytes memory withdrawCredential = vaultFactory.getValidatorWithdrawCredential(withdrawVault);
        _validateKeys(_pubKey, withdrawCredential, _signature, _depositDataRoot);
        vaultFactory.deployWithdrawVault(_poolId,_operatorId, totalKeys);
        validatorRegistry[nextValidatorId] = Validator(
            ValidatorStatus.INITIALIZED,
            false,
            _pubKey,
            _signature,
            withdrawCredential,
            _depositDataRoot,
            _operatorId,
            msg.value,
            0
        );
        validatorIdByPubKey[_pubKey] = nextValidatorId;
        poolHelper.incrementInitializedValidatorKeys(_poolId);
        staderOperatorRegistry.incrementInitializedValidatorsCount(msg.sender);
        nextValidatorId++;
    }

    function _updatePoolHelper(address _staderPoolHelper)
        internal virtual
    {
        poolHelper = IStaderPoolHelper(_staderPoolHelper);
    }

    function _updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status) internal{
        uint256 validatorId = validatorIdByPubKey[_pubKey];
        if(validatorId == 0) revert PubKeyDoesNotExist();
        validatorRegistry[validatorId].status = _status;
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

    function _sendValue(uint256 _amount) internal {
        if (address(this).balance < _amount) revert InSufficientBalance();

        (,,address poolAddress,,,,,,) = poolHelper.staderPool(1);

        // solhint-disable-next-line
        (bool success, ) = payable(poolAddress).call{value: _amount}('');
        if (!success) revert TransferFailed();
    }
}
