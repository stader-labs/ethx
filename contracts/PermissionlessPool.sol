// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IVaultFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract PermissionlessPool is IStaderPoolBase, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint8 public constant poolId = 1;

    address public nodeRegistryAddress;
    address public ethDepositContract;
    address public vaultFactoryAddress;
    address public staderStakePoolManager;

    bytes32 public constant PERMISSIONLESS_POOL_ADMIN = keccak256('PERMISSIONLESS_POOL_ADMIN');
    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONLESS_NODE_REGISTRY = keccak256('PERMISSIONLESS_NODE_REGISTRY');

    uint256 public constant DEPOSIT_NODE_BOND = 3 ether;
    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant DEPOSIT_SIZE = 31 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint256 public constant TOTAL_FEE = 10000;

    /// @inheritdoc IStaderPoolBase
    uint256 public override protocolFee;

    /// @inheritdoc IStaderPoolBase
    uint256 public override operatorFee;

    function initialize(
        address _adminOwner,
        address _nodeRegistryAddress,
        address _ethDepositContract,
        address _vaultFactoryAddress,
        address _staderStakePoolManager
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_nodeRegistryAddress);
        Address.checkNonZeroAddress(_ethDepositContract);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_staderStakePoolManager);
        __AccessControl_init_unchained();
        __Pausable_init();
        nodeRegistryAddress = _nodeRegistryAddress;
        ethDepositContract = _ethDepositContract;
        vaultFactoryAddress = _vaultFactoryAddress;
        staderStakePoolManager = _staderStakePoolManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    // receive `DEPOSIT_NODE_BOND` collateral ETH from permissionless node registry
    function receiveRemainingCollateralETH() external payable onlyRole(PERMISSIONLESS_NODE_REGISTRY) {
        emit ReceivedCollateralETH(msg.value);
    }

    //TODO sanjay merge setProtocolFee and setOperatorFee function
    /// @inheritdoc IStaderPoolBase
    function setProtocolFee(uint256 _protocolFee) external onlyRole(PERMISSIONLESS_POOL_ADMIN) {
        if (_protocolFee > TOTAL_FEE) revert ProtocolFeeMoreThanTOTAL_FEE();
        if (protocolFee == _protocolFee) revert ProtocolFeeUnchanged();

        protocolFee = _protocolFee;

        emit ProtocolFeeUpdated(_protocolFee);
    }

    /// @inheritdoc IStaderPoolBase
    function setOperatorFee(uint256 _operatorFee) external onlyRole(PERMISSIONLESS_POOL_ADMIN) {
        if (_operatorFee > TOTAL_FEE) revert OperatorFeeMoreThanTOTAL_FEE();
        if (operatorFee == _operatorFee) revert OperatorFeeUnchanged();

        operatorFee = _operatorFee;

        emit OperatorFeeUpdated(_operatorFee);
    }

    /**
     * @notice pre deposit for permission less validator to avoid front running
     * @dev only permissionless node registry can call
     * @param _pubkey public key array of validators
     * @param _preDepositSignature signature array of validators for 1ETH deposit
     * @param _operatorId operator Id of the NO
     * @param _operatorTotalKeys total keys of operator at the starting of adding new keys
     */
    function preDepositOnBeaconChain(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        uint256 _operatorId,
        uint256 _operatorTotalKeys
    ) external payable onlyRole(PERMISSIONLESS_NODE_REGISTRY) {
        for (uint256 i = 0; i < _pubkey.length; i++) {
            address withdrawVault = IVaultFactory(vaultFactoryAddress).computeWithdrawVaultAddress(
                poolId,
                _operatorId,
                _operatorTotalKeys + i
            );
            bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                withdrawVault
            );

            bytes32 depositDataRoot = this.computeDepositDataRoot(
                _pubkey[i],
                _preDepositSignature[i],
                withdrawCredential,
                PRE_DEPOSIT_SIZE
            );
            //slither-disable-next-line arbitrary-send-eth
            IDepositContract(ethDepositContract).deposit{value: PRE_DEPOSIT_SIZE}(
                _pubkey[i],
                withdrawCredential,
                _preDepositSignature[i],
                depositDataRoot
            );
            emit ValidatorPreDepositedOnBeaconChain(_pubkey[i]);
        }
    }

    /**
     * @notice receives eth from pool manager to deposit for validators on beacon chain
     * @dev deposit validator taking care of pool capacity
     */
    function stakeUserETHToBeaconChain() external payable override onlyRole(POOL_MANAGER) {
        uint256 requiredValidators = msg.value / (DEPOSIT_SIZE - DEPOSIT_NODE_BOND);
        IPermissionlessNodeRegistry(nodeRegistryAddress).transferCollateralToPool(
            requiredValidators * DEPOSIT_NODE_BOND
        );

        uint256 depositQueueStartIndex = IPermissionlessNodeRegistry(nodeRegistryAddress).nextQueuedValidatorIndex();
        for (uint256 i = depositQueueStartIndex; i < requiredValidators + depositQueueStartIndex; i++) {
            uint256 validatorId = IPermissionlessNodeRegistry(nodeRegistryAddress).queuedValidators(i);
            _fullDepositOnBeaconChain(validatorId);
        }
        IPermissionlessNodeRegistry(nodeRegistryAddress).updateNextQueuedValidatorIndex(
            depositQueueStartIndex + requiredValidators
        );
        IPermissionlessNodeRegistry(nodeRegistryAddress).increaseTotalActiveValidatorCount(requiredValidators);
        // balance must be 0 at this point
        assert(address(this).balance == 0);
    }

    /**
     * @notice update the stader stake pool manager address
     * @dev only admin can call
     * @param _staderStakePoolManager address of stader stake pool manager
     */
    function updateStaderStakePoolManager(address _staderStakePoolManager)
        external
        override
        onlyRole(PERMISSIONLESS_POOL_ADMIN)
    {
        Address.checkNonZeroAddress(_staderStakePoolManager);
        staderStakePoolManager = _staderStakePoolManager;
        emit UpdatedStaderStakePoolManager(staderStakePoolManager);
    }

    /**
     * @notice update the node registry address
     * @dev only admin can call
     * @param _nodeRegistryAddress address of node registry
     */
    function updateNodeRegistryAddress(address _nodeRegistryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_POOL_ADMIN)
    {
        Address.checkNonZeroAddress(_nodeRegistryAddress);
        nodeRegistryAddress = _nodeRegistryAddress;
        emit UpdatedNodeRegistryAddress(_nodeRegistryAddress);
    }

    /**
     * @notice update the vault factory address
     * @dev only admin can call
     * @param _vaultFactoryAddress address of vault factory
     */
    function updateVaultFactoryAddress(address _vaultFactoryAddress)
        external
        override
        onlyRole(PERMISSIONLESS_POOL_ADMIN)
    {
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        vaultFactoryAddress = _vaultFactoryAddress;
        emit UpdatedVaultFactoryAddress(_vaultFactoryAddress);
    }

    // @inheritdoc IStaderPoolBase
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        return INodeRegistry(nodeRegistryAddress).getOperator(_pubkey);
    }

    /// @inheritdoc IStaderPoolBase
    function getSocializingPoolAddress() external view returns (address) {
        return IPermissionlessNodeRegistry(nodeRegistryAddress).elRewardSocializePool();
    }

    /**
     * @notice return total queued keys for permissionless pool
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalQueuedValidatorCount();
    }

    /**
     * @notice return total active keys for permissionless pool
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalActiveValidatorCount();
    }

    /**
     * @notice get all validator which has user balance on beacon chain
     */
    function getAllActiveValidators() public view override returns (Validator[] memory) {
        return INodeRegistry(nodeRegistryAddress).getAllActiveValidators();
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return INodeRegistry(nodeRegistryAddress).getValidator(_pubkey);
    }

    /**
     * @notice returns the total non terminal keys of a operator
     */
    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) external view override returns (uint256) {
        return
            INodeRegistry(nodeRegistryAddress).getOperatorTotalNonTerminalKeys(_nodeOperator, _startIndex, _endIndex);
    }

    function getCollateralETH() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getCollateralETH();
    }

    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return INodeRegistry(nodeRegistryAddress).isExistingPubkey(_pubkey);
    }

    // @notice calculate the deposit data root based on pubkey, signature, withdrawCredential and amount
    // formula based on ethereum deposit contract
    function computeDepositDataRoot(
        bytes calldata _pubkey,
        bytes calldata _signature,
        bytes calldata _withdrawCredential,
        uint256 _depositAmount
    ) external pure returns (bytes32) {
        bytes memory amount = to_little_endian_64(_depositAmount);
        bytes32 pubkey_root = sha256(abi.encodePacked(_pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(_signature[:64])),
                sha256(abi.encodePacked(_signature[64:], bytes32(0)))
            )
        );
        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(pubkey_root, _withdrawCredential)),
                    sha256(abi.encodePacked(amount, bytes24(0), signature_root))
                )
            );
    }

    function _fullDepositOnBeaconChain(uint256 _validatorId) internal {
        (
            ,
            bytes memory pubkey,
            ,
            bytes memory depositSignature,
            address withdrawVaultAddress,
            ,
            ,
            ,

        ) = IPermissionlessNodeRegistry(nodeRegistryAddress).validatorRegistry(_validatorId);

        bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVaultAddress
        );

        bytes32 depositDataRoot = this.computeDepositDataRoot(
            pubkey,
            depositSignature,
            withdrawCredential,
            DEPOSIT_SIZE
        );
        IDepositContract(ethDepositContract).deposit{value: DEPOSIT_SIZE}(
            pubkey,
            withdrawCredential,
            depositSignature,
            depositDataRoot
        );
        IPermissionlessNodeRegistry(nodeRegistryAddress).updateDepositStatusAndTime(_validatorId);
        emit ValidatorDepositedOnBeaconChain(_validatorId, pubkey);
    }

    //ethereum deposit contract function to get amount into little_endian_64
    function to_little_endian_64(uint256 _depositAmount) internal pure returns (bytes memory ret) {
        uint64 value = uint64(_depositAmount / 1 gwei);

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
}
