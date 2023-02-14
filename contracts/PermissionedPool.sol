pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/BytesLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IStaderPoolBase.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderPoolSelector.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionedNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract PermissionedPool is IStaderPoolBase, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    address public poolHelper;
    address public staderStakePoolManager;
    address public ethValidatorDeposit;

    bytes32 public constant PERMISSIONED_POOL_ADMIN = keccak256('PERMISSIONED_POOL_ADMIN');

    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0040597307000000;

    function initialize(address _adminOwner, address _ethValidatorDeposit) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_ethValidatorDeposit);
        __Pausable_init();
        __AccessControl_init_unchained();
        ethValidatorDeposit = _ethValidatorDeposit;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    receive() external payable {}

    /**
     * @notice receives eth from pool Manager to register validators
     * @dev deposit validator taking care of pool capacity
     * send back the excess amount of ETH back to poolManager
     */
    function registerValidatorsOnBeacon() external payable override {
        uint256 requiredValidators = address(this).balance / DEPOSIT_SIZE;
        (, , , address nodeRegistry, , uint256 queuedValidatorKeys, , ) = IStaderPoolSelector(poolHelper).staderPool(2);
        requiredValidators = Math.min(requiredValidators, queuedValidatorKeys);

        if (requiredValidators == 0) revert NotEnoughValidatorToDeposit();
        uint256[] memory operatorWiseValidatorToDeposit = IPermissionedNodeRegistry(nodeRegistry)
            .computeOperatorWiseValidatorsToDeposit(requiredValidators);

        for (uint256 i = 1; i < operatorWiseValidatorToDeposit.length; i++) {
            uint256 validatorToDeposit = operatorWiseValidatorToDeposit[i];
            if (validatorToDeposit == 0) continue;
            address operator = IPermissionedNodeRegistry(nodeRegistry).operatorByOperatorId(i);
            (, , , , uint256 nextQueuedValidatorIndex, , , , ) = IPermissionedNodeRegistry(nodeRegistry)
                .operatorRegistry(operator);

            for (
                uint256 index = nextQueuedValidatorIndex;
                index < nextQueuedValidatorIndex + validatorToDeposit;
                index++
            ) {
                uint256 validatorId = IPermissionedNodeRegistry(nodeRegistry).operatorQueuedValidators(i, index);

                (
                    ValidatorStatus status,
                    ,
                    bytes memory pubKey,
                    bytes memory signature,
                    bytes memory withdrawalAddress,

                ) = IPermissionedNodeRegistry(nodeRegistry).validatorRegistry(validatorId);
                // node operator might withdraw validator in queue
                if (status != ValidatorStatus.PRE_DEPOSIT) continue;

                bytes32 depositDataRoot = _computeDepositDataRoot(pubKey, signature, withdrawalAddress);

                IDepositContract(ethValidatorDeposit).deposit{value: DEPOSIT_SIZE}(
                    pubKey,
                    withdrawalAddress,
                    signature,
                    depositDataRoot
                );
                IPermissionedNodeRegistry(nodeRegistry).updateValidatorStatus(pubKey, ValidatorStatus.DEPOSITED);
                IPermissionedNodeRegistry(nodeRegistry).reduceQueuedValidatorsCount(operator);
                IPermissionedNodeRegistry(nodeRegistry).incrementActiveValidatorsCount(operator);
                emit ValidatorRegisteredOnBeacon(validatorId, pubKey);
            }

            IStaderPoolSelector(poolHelper).reduceQueuedValidatorKeys(2, validatorToDeposit);
            IStaderPoolSelector(poolHelper).incrementActiveValidatorKeys(2, validatorToDeposit);
            IPermissionedNodeRegistry(nodeRegistry).updateQueuedValidatorIndex(
                operator,
                nextQueuedValidatorIndex + validatorToDeposit
            );
        }
        if (address(this).balance > 0) {
            IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: address(this).balance}(2);
        }
    }

    /**
     * @notice update the address of pool Helper
     * @dev only admin can call
     * @param _poolHelper address of pool helper
     */
    function updatePoolSelector(address _poolHelper) external override onlyRole(PERMISSIONED_POOL_ADMIN) {
        Address.checkNonZeroAddress(_poolHelper);
        poolHelper = _poolHelper;
        emit UpdatedPoolHelper(poolHelper);
    }

    /**
     * @notice update the stader stake pool manager address
     * @dev only admin can call
     * @param _staderStakePoolManager address of stader stake pool manager
     */
    function updateStaderStakePoolManager(address _staderStakePoolManager)
        external
        override
        onlyRole(PERMISSIONED_POOL_ADMIN)
    {
        Address.checkNonZeroAddress(_staderStakePoolManager);
        staderStakePoolManager = _staderStakePoolManager;
        emit UpdatedStaderStakePoolManager(staderStakePoolManager);
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
