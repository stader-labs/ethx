pragma solidity ^0.8.16;

import './library/Address.sol';
import './library/BytesLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IVaultFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionedNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract PermissionedPool is IStaderPoolBase, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint8 public constant poolId = 2;
    uint8 internal constant singleCount = 1;
    uint64 internal constant PRE_DEPOSIT_SIZE_IN_GWEI_LE64 = 0x00e40b5402000000;
    uint64 internal constant DEPOSIT_SIZE_IN_GWEI_LE64 = 0x0076be3707000000;

    address public nodeRegistryAddress;
    address public ethValidatorDeposit;
    address public vaultFactoryAddress;
    address public staderStakePoolManager;

    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONED_POOL_ADMIN = keccak256('PERMISSIONED_POOL_ADMIN');
    bytes32 public constant STADER_DAO = keccak256('STADER_DAO');

    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant DEPOSIT_SIZE = 31 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint256 public depositBatchSize;
    uint256 public nextDepositBatchId;
    uint256 public nextProcessedBatchId;

    mapping(uint256 => uint256[]) public preDepositValidatorBatch;
    mapping(uint256 => bool) public deactivatedOperators;

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

        //initialize `preDepositValidatorBatch` with empty array at index 0
        preDepositValidatorBatch[0].push();
        // preDepositValidatorBatch starts at index 1
        depositBatchSize = 1;
        nextDepositBatchId = 1;
        nextProcessedBatchId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    receive() external payable {}

    /**
     * @notice receives eth from pool Manager to register validators
     * @dev deposit validator taking care of pool capacity
     * send back the excess amount of ETH back to poolManager
     */
    function registerOnBeaconChain() external payable override onlyRole(POOL_MANAGER) {
        uint256 requiredValidators = msg.value / DEPOSIT_SIZE;
        uint256[] memory selectedOperatorCapacity = IPermissionedNodeRegistry(nodeRegistryAddress)
            .computeOperatorAllocationForDeposit(requiredValidators);

        // i is the operator ID
        for (uint256 i = 1; i < selectedOperatorCapacity.length; i++) {
            uint256 validatorToDeposit = selectedOperatorCapacity[i];
            if (validatorToDeposit == 0) continue;
            (, , , , uint256 nextQueuedValidatorIndex, , , , ) = IPermissionedNodeRegistry(nodeRegistryAddress)
                .operatorStructById(i);

            for (
                uint256 index = nextQueuedValidatorIndex;
                index < nextQueuedValidatorIndex + validatorToDeposit;
                index++
            ) {
                uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).operatorQueuedValidators(i, index);

                (
                    ,
                    ,
                    bytes memory pubkey,
                    bytes memory signature,
                    address withdrawVaultAddress,

                ) = IPermissionedNodeRegistry(nodeRegistryAddress).validatorRegistry(validatorId);

                bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                    withdrawVaultAddress
                );
                bytes32 depositDataRoot = _computeDepositDataRoot(
                    pubkey,
                    signature,
                    withdrawCredential,
                    PRE_DEPOSIT_SIZE_IN_GWEI_LE64
                );

                IDepositContract(ethValidatorDeposit).deposit{value: PRE_DEPOSIT_SIZE}(
                    pubkey,
                    withdrawCredential,
                    signature,
                    depositDataRoot
                );
                IPermissionedNodeRegistry(nodeRegistryAddress).updateValidatorStatus(pubkey, ValidatorStatus.DEPOSITED);
                preDepositValidatorBatch[depositBatchSize].push(validatorId);
                emit ValidatorPreDepositedOnBeaconChain(validatorId, pubkey);
            }

            IPermissionedNodeRegistry(nodeRegistryAddress).updateQueuedAndActiveValidatorsCount(i, validatorToDeposit);
            IPermissionedNodeRegistry(nodeRegistryAddress).updateQueuedValidatorIndex(
                i,
                nextQueuedValidatorIndex + validatorToDeposit
            );
        }
        depositBatchSize++;
    }

    /**
     * @notice reports the front running validator
     * @dev only stader DAO can call
     * @param _validatorIds array of validator IDs which got front running deposit
     */
    function reportFrontRunValidators(uint256[] calldata _validatorIds) external onlyRole(STADER_DAO) {
        IPermissionedNodeRegistry(nodeRegistryAddress).updateFrontRunValidator(_validatorIds);
        nextProcessedBatchId++;
    }

    /**
     * @notice deposit `DEPOSIT_SIZE` for the processed batch of preDeposited Validator
     * @dev anyone can call, check of available processed batch which are not deposited
     */
    function depositOnBeaconChain() external {
        if (nextDepositBatchId >= nextProcessedBatchId) revert NotEnoughProcessedBatchToDeposit();
        while (nextDepositBatchId < nextProcessedBatchId) {
            for (uint256 i = 0; i < preDepositValidatorBatch[nextDepositBatchId].length; i++) {
                uint256 validatorId = preDepositValidatorBatch[nextDepositBatchId][i];
                (
                    ,
                    bool isFrontRun,
                    bytes memory pubkey,
                    bytes memory signature,
                    address withdrawVaultAddress,
                    uint256 operatorId
                ) = IPermissionedNodeRegistry(nodeRegistryAddress).validatorRegistry(validatorId);
                if (isFrontRun) {
                    IPermissionedNodeRegistry(nodeRegistryAddress).updateActiveAndWithdrawnValidatorsCount(
                        operatorId,
                        singleCount
                    );
                    if (!deactivatedOperators[operatorId]) {
                        IPermissionedNodeRegistry(nodeRegistryAddress).deactivateNodeOperator(operatorId);
                        deactivatedOperators[operatorId] = true;
                    }
                    continue;
                }
                bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                    withdrawVaultAddress
                );
                bytes32 depositDataRoot = _computeDepositDataRoot(
                    pubkey,
                    signature,
                    withdrawCredential,
                    DEPOSIT_SIZE_IN_GWEI_LE64
                );

                IDepositContract(ethValidatorDeposit).deposit{value: DEPOSIT_SIZE}(
                    pubkey,
                    withdrawCredential,
                    signature,
                    depositDataRoot
                );
                emit ValidatorDepositedOnBeaconChain(validatorId, pubkey);
            }
            nextDepositBatchId++;
        }
        if (nextDepositBatchId == depositBatchSize) {
            IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: address(this).balance}(
                poolId
            );
        }
    }

    /**
     * @notice return total queued keys for permissioned pool
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalQueuedValidatorCount();
    }

    /**
     * @notice return total active keys for permissioned pool
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getTotalActiveValidatorCount();
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

    /**
     * @notice update the node registry address
     * @dev only admin can call
     * @param _nodeRegistryAddress address of node registry
     */
    function updateNodeRegistryAddress(address _nodeRegistryAddress)
        external
        override
        onlyRole(PERMISSIONED_POOL_ADMIN)
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
        onlyRole(PERMISSIONED_POOL_ADMIN)
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
        uint64 _AMOUNT_IN_GWEI_LE64
    ) private pure returns (bytes32) {
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
                    sha256(abi.encodePacked(_AMOUNT_IN_GWEI_LE64, bytes24(0), signatureRoot))
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
