// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/BytesLib.sol';
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
    address public ethValidatorDeposit;
    address public vaultFactoryAddress;
    address public staderStakePoolManager;

    bytes32 public constant PERMISSIONLESS_POOL_ADMIN = keccak256('PERMISSIONLESS_POOL_ADMIN');
    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONLESS_NODE_REGISTRY = keccak256('PERMISSIONLESS_NODE_REGISTRY');

    uint256 public constant DEPOSIT_NODE_BOND = 3 ether;
    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant DEPOSIT_SIZE = 31 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;

    function initialize(
        address _adminOwner,
        address _nodeRegistryAddress,
        address _ethValidatorDeposit,
        address _vaultFactoryAddress,
        address _staderStakePoolManager
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_nodeRegistryAddress);
        Address.checkNonZeroAddress(_ethValidatorDeposit);
        Address.checkNonZeroAddress(_vaultFactoryAddress);
        Address.checkNonZeroAddress(_staderStakePoolManager);
        __Pausable_init();
        __AccessControl_init_unchained();
        nodeRegistryAddress = _nodeRegistryAddress;
        ethValidatorDeposit = _ethValidatorDeposit;
        vaultFactoryAddress = _vaultFactoryAddress;
        staderStakePoolManager = _staderStakePoolManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    // receive to get bond ETH from permissionless node registry
    receive() external payable {}

    /**
     * @notice pre deposit for permission less validator to avoid front running
     * @dev only permissionless node registry can call
     * @param _pubkey public key of validator
     * @param _signature signature of validator
     * @param withdrawVault withdraw address to se set for validator
     */
    function preDepositOnBeacon(
        bytes calldata _pubkey,
        bytes calldata _signature,
        address withdrawVault
    ) external payable onlyRole(PERMISSIONLESS_NODE_REGISTRY) {
        bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVault
        );

        bytes32 depositDataRoot = _computeDepositDataRoot(_pubkey, _signature, withdrawCredential, PRE_DEPOSIT_SIZE);
        IDepositContract(ethValidatorDeposit).deposit{value: PRE_DEPOSIT_SIZE}(
            _pubkey,
            withdrawCredential,
            _signature,
            depositDataRoot
        );
        uint256 validatorId = IPermissionlessNodeRegistry(nodeRegistryAddress).validatorIdByPubkey(_pubkey);
        emit ValidatorPreDepositedOnBeaconChain(validatorId, _pubkey);
    }

    /**
     * @notice receives eth from pool Manager to register validators
     * @dev deposit validator taking care of pool capacity
     * send back the excess amount of ETH back to poolManager
     */
    function registerOnBeaconChain() external payable onlyRole(POOL_MANAGER) {
        uint256 requiredValidators = address(this).balance / (DEPOSIT_SIZE - DEPOSIT_NODE_BOND);
        IPermissionlessNodeRegistry(nodeRegistryAddress).transferCollateralToPool(
            requiredValidators * DEPOSIT_NODE_BOND
        );

        uint256 depositQueueStartIndex = IPermissionlessNodeRegistry(nodeRegistryAddress).nextQueuedValidatorIndex();
        for (uint256 i = depositQueueStartIndex; i < requiredValidators + depositQueueStartIndex; i++) {
            uint256 validatorId = IPermissionlessNodeRegistry(nodeRegistryAddress).queuedValidators(i);
            (
                ,
                ,
                bytes memory pubkey,
                bytes memory signature,
                address withdrawVaultAddress,
                uint256 operatorId,

            ) = IPermissionlessNodeRegistry(nodeRegistryAddress).validatorRegistry(validatorId);

            bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                withdrawVaultAddress
            );

            bytes32 depositDataRoot = _computeDepositDataRoot(pubkey, signature, withdrawCredential, DEPOSIT_SIZE);
            IDepositContract(ethValidatorDeposit).deposit{value: DEPOSIT_SIZE}(
                pubkey,
                withdrawCredential,
                signature,
                depositDataRoot
            );

            IPermissionlessNodeRegistry(nodeRegistryAddress).updateValidatorStatus(pubkey, ValidatorStatus.DEPOSITED);
            IPermissionlessNodeRegistry(nodeRegistryAddress).updateQueuedAndActiveValidatorsCount(operatorId);
            emit ValidatorDepositedOnBeaconChain(validatorId, pubkey);
        }

        IPermissionlessNodeRegistry(nodeRegistryAddress).updateNextQueuedValidatorIndex(requiredValidators);
        if (address(this).balance > 0) {
            //slither-disable-next-line arbitrary-send-eth
            IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: address(this).balance}(
                poolId
            );
        }
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
     * @notice returns the total non withdrawn keys of a operator
     */
    function getOperatorTotalNonWithdrawnKeys(address _nodeOperator) external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getOperatorTotalNonWithdrawnKeys(_nodeOperator);
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

    function getAllActiveValidators() public view override returns (Validator[] memory) {
        return INodeRegistry(nodeRegistryAddress).getAllActiveValidators();
    }

    function getValidator(bytes memory _pubkey) external view returns (Validator memory) {
        return INodeRegistry(nodeRegistryAddress).getValidator(_pubkey);
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

    /// @notice calculate the deposit data root based on pubkey, signature and withdrawCredential
    function _computeDepositDataRoot(
        bytes memory _pubkey,
        bytes memory _signature,
        bytes memory _withdrawCredential,
        uint256 _depositAmount
    ) private pure returns (bytes32) {
        bytes memory amount = to_little_endian_64(_depositAmount);
        bytes32 publicKeyRoot = sha256(_pad64(_pubkey));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(BytesLib.slice(_signature, 0, 64)),
                sha256(_pad64(BytesLib.slice(_signature, 64, SIGNATURE_LENGTH - 64)))
            )
        );

        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(publicKeyRoot, _withdrawCredential)),
                    sha256(abi.encodePacked(amount, bytes24(0), signatureRoot))
                )
            );
    }

    /// @dev Padding memory array with zeroes up to 64 bytes on the right
    /// @param _b Memory array of size 32 .. 64
    function _pad64(bytes memory _b) internal pure returns (bytes memory) {
        assert(_b.length >= 32 && _b.length <= 64);
        if (64 == _b.length) return _b;

        bytes memory zero32 = new bytes(32);
        assembly {
            mstore(add(zero32, 0x20), 0)
        }

        if (32 == _b.length) return BytesLib.concat(_b, zero32);
        else return BytesLib.concat(_b, BytesLib.slice(zero32, 0, uint256(64) - _b.length));
    }

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
