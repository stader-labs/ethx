pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/BytesLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IStaderPoolBase.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract PermissionlessPool is IStaderPoolBase, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint8 public constant poolId = 1;
    address public staderStakePoolManager;
    address public ethValidatorDeposit;
    address public nodeRegistryAddress;

    bytes32 public constant PERMISSIONLESS_POOL_ADMIN = keccak256('PERMISSIONLESS_POOL_ADMIN');

    uint256 public constant NODE_BOND = 4 ether;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;

    function initialize(
        address _adminOwner,
        address _ethValidatorDeposit,
        address _staderStakePoolManger,
        address _nodeRegistryAddress
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_ethValidatorDeposit);
        Address.checkNonZeroAddress(_staderStakePoolManger);
        Address.checkNonZeroAddress(_nodeRegistryAddress);
        __Pausable_init();
        __AccessControl_init_unchained();
        ethValidatorDeposit = _ethValidatorDeposit;
        staderStakePoolManager = _staderStakePoolManger;
        nodeRegistryAddress = _nodeRegistryAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    // receive to get bond ETH from permissionless node registry
    receive() external payable {}

    /**
     * @notice receives eth from pool Manager to register validators
     * @dev deposit validator taking care of pool capacity
     * send back the excess amount of ETH back to poolManager
     */
    function registerValidatorsOnBeacon() external payable override {
        uint256 requiredValidators = address(this).balance / (DEPOSIT_SIZE - NODE_BOND);
        uint256 queuedValidatorKeys = INodeRegistry(nodeRegistryAddress).getTotalQueuedValidatorCount();

        requiredValidators = Math.min(queuedValidatorKeys, requiredValidators);
        if (requiredValidators == 0) revert NotEnoughValidatorToDeposit();

        IPermissionlessNodeRegistry(nodeRegistryAddress).transferCollateralToPool(requiredValidators * NODE_BOND);

        uint256 depositQueueStartIndex = IPermissionlessNodeRegistry(nodeRegistryAddress).nextQueuedValidatorIndex();
        for (uint256 i = depositQueueStartIndex; i < requiredValidators + depositQueueStartIndex; i++) {
            uint256 validatorId = IPermissionlessNodeRegistry(nodeRegistryAddress).queuedValidators(i);
            (
                ,
                bytes memory pubKey,
                bytes memory signature,
                bytes memory withdrawalAddress,
                ,
                ,

            ) = IPermissionlessNodeRegistry(nodeRegistryAddress).validatorRegistry(validatorId);

            bytes32 depositDataRoot = _computeDepositDataRoot(pubKey, signature, withdrawalAddress);
            IDepositContract(ethValidatorDeposit).deposit{value: DEPOSIT_SIZE}(
                pubKey,
                withdrawalAddress,
                signature,
                depositDataRoot
            );

            IPermissionlessNodeRegistry(nodeRegistryAddress).updateValidatorStatus(pubKey, ValidatorStatus.DEPOSITED);
            emit ValidatorRegisteredOnBeacon(validatorId, pubKey);
        }

        IPermissionlessNodeRegistry(nodeRegistryAddress).reduceTotalQueuedValidatorsCount(requiredValidators);
        IPermissionlessNodeRegistry(nodeRegistryAddress).increaseTotalActiveValidatorsCount(requiredValidators);
        IPermissionlessNodeRegistry(nodeRegistryAddress).updateNextQueuedValidatorIndex(requiredValidators);
        if (address(this).balance > 0) {
            IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: address(this).balance}(
                poolId
            );
        }
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

    function getTotalValidatorCount() external view override returns (uint256) {
        return
            this.getTotalInitializedValidatorCount() +
            this.getTotalActiveValidatorCount() +
            this.getTotalQueuedValidatorCount() +
            this.getTotalWithdrawnValidatorCount();
    }

    function getTotalInitializedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalInitializedValidatorCount();
    }

    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalActiveValidatorCount();
    }

    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalQueuedValidatorCount();
    }

    function getTotalWithdrawnValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalWithdrawnValidatorCount();
    }

    /// @notice calculate the deposit data root based on pubkey, signature and withdrawCredential
    function _computeDepositDataRoot(
        bytes memory _pubKey,
        bytes memory _signature,
        bytes memory _withdrawCredential
    ) private pure returns (bytes32) {
        bytes32 publicKeyRoot = sha256(_pad64(_pubKey));
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
                    sha256(abi.encodePacked(DEPOSIT_SIZE_IN_GWEI_LE64, bytes24(0), signatureRoot))
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
}
