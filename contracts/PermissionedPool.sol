// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
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
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract PermissionedPool is
    IStaderPoolBase,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;

    uint8 public constant poolId = 2;
    address public nodeRegistryAddress;
    address public ethDepositContract;
    address public vaultFactoryAddress;
    address public staderStakePoolManager;

    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONED_POOL_ADMIN = keccak256('PERMISSIONED_POOL_ADMIN');
    bytes32 public constant STADER_ORACLE = keccak256('STADER_ORACLE');

    uint256 public balanceForDeposit;
    uint256 public nextIndexToDeposit;
    uint256 public VERIFIED_KEYS_BATCH_SIZE;
    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant DEPOSIT_SIZE = 31 ether;
    uint256 public constant FULL_DEPOSIT_SIZE = 32 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;
    uint256 public constant TOTAL_FEE = 10000;

    // @inheritdoc IStaderPoolBase
    uint256 public override protocolFee;

    // @inheritdoc IStaderPoolBase
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
        __ReentrancyGuard_init();
        VERIFIED_KEYS_BATCH_SIZE = 100;
        nodeRegistryAddress = _nodeRegistryAddress;
        ethDepositContract = _ethDepositContract;
        vaultFactoryAddress = _vaultFactoryAddress;
        staderStakePoolManager = _staderStakePoolManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    receive() external payable {}

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkeys,
        bytes[] calldata _frontRunPubkeys,
        bytes[] calldata _invalidSignaturePubkeys
    ) external nonReentrant onlyRole(STADER_ORACLE) {
        uint256 verifiedValidatorsLength = _readyToDepositPubkeys.length;
        if (verifiedValidatorsLength > VERIFIED_KEYS_BATCH_SIZE) revert TooManyVerifiedKeysToDeposit();

        uint256 frontRunValidatorsLength = _frontRunPubkeys.length;
        uint256 invalidSignatureValidatorsLength = _invalidSignaturePubkeys.length;

        if (frontRunValidatorsLength > 0) {
            IPermissionedNodeRegistry(nodeRegistryAddress).reportFrontRunValidator(_frontRunPubkeys);
        }

        if (invalidSignatureValidatorsLength > 0) {
            IPermissionedNodeRegistry(nodeRegistryAddress).reportInvalidSignatureValidator(_invalidSignaturePubkeys);
        }

        // send back 31 ETH for front run and invalid signature validators back to pool manager
        // These counts are correct because any double reporting of frontrun/invalid statuses results in an error.
        uint256 amountToSendToPoolManager = (frontRunValidatorsLength + invalidSignatureValidatorsLength) *
            DEPOSIT_SIZE;
        // update the remaining balance for 31 ETH deposit by subtracting the amount, sending to SSMP
        // for invalid or front run keys and `verifiedValidatorLength` keys 31 ETH deposit amount
        balanceForDeposit -= (amountToSendToPoolManager + verifiedValidatorsLength * DEPOSIT_SIZE);
        //slither-disable-next-line arbitrary-send-eth
        IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: amountToSendToPoolManager}(
            poolId
        );

        for (uint256 i = 0; i < verifiedValidatorsLength; i++) {
            IPermissionedNodeRegistry(nodeRegistryAddress).onlyPreDepositValidator(_readyToDepositPubkeys[i]);
            // TODO sanjay update 31ETH limbo
            _fullDepositOnBeaconChain(_readyToDepositPubkeys[i]);
        }
    }

    // @inheritdoc IStaderPoolBase
    function setProtocolFee(uint256 _protocolFee) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        if (_protocolFee > TOTAL_FEE) revert ProtocolFeeMoreThanTOTAL_FEE();
        if (protocolFee == _protocolFee) revert ProtocolFeeUnchanged();

        protocolFee = _protocolFee;

        emit ProtocolFeeUpdated(_protocolFee);
    }

    // @inheritdoc IStaderPoolBase
    function setOperatorFee(uint256 _operatorFee) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        if (_operatorFee > TOTAL_FEE) revert OperatorFeeMoreThanTOTAL_FEE();
        if (operatorFee == _operatorFee) revert OperatorFeeUnchanged();

        operatorFee = _operatorFee;

        emit OperatorFeeUpdated(_operatorFee);
    }

    /**
     * @notice receives eth from pool manager to deposit for validators on beacon chain
     * @dev deposit PRE_DEPOSIT_SIZE of ETH for validators while adhering to pool capacity.
     */
    function stakeUserETHToBeaconChain() external payable override onlyRole(POOL_MANAGER) {
        uint256 requiredValidators = msg.value / FULL_DEPOSIT_SIZE;
        uint256[] memory selectedOperatorCapacity = IPermissionedNodeRegistry(nodeRegistryAddress)
            .computeOperatorAllocationForDeposit(requiredValidators);

        // i is the operator ID
        for (uint16 i = 1; i < selectedOperatorCapacity.length; i++) {
            uint256 validatorToDeposit = selectedOperatorCapacity[i];
            if (validatorToDeposit == 0) continue;
            uint256 nextQueuedValidatorIndex = IPermissionedNodeRegistry(nodeRegistryAddress)
                .nextQueuedValidatorIndexByOperatorId(i);

            for (
                uint256 index = nextQueuedValidatorIndex;
                index < nextQueuedValidatorIndex + validatorToDeposit;
                index++
            ) {
                uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).validatorIdsByOperatorId(i, index);
                // TODO sanjay update 1ETH limbo
                _preDepositOnBeaconChain(validatorId);
            }
            IPermissionedNodeRegistry(nodeRegistryAddress).updateQueuedValidatorIndex(
                i,
                nextQueuedValidatorIndex + validatorToDeposit
            );
        }
        balanceForDeposit += requiredValidators * DEPOSIT_SIZE;
        IPermissionedNodeRegistry(nodeRegistryAddress).increaseTotalActiveValidatorCount(requiredValidators);
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
     * @notice returns the total non withdrawn keys of a operator
     */
    function getOperatorTotalNonWithdrawnKeys(
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) external view override returns (uint256) {
        return
            INodeRegistry(nodeRegistryAddress).getOperatorTotalNonWithdrawnKeys(_nodeOperator, _startIndex, _endIndex);
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

    function getAllActiveValidators() public view override returns (Validator[] memory) {
        return INodeRegistry(nodeRegistryAddress).getAllActiveValidators();
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return INodeRegistry(nodeRegistryAddress).getValidator(_pubkey);
    }

    // @inheritdoc IStaderPoolBase
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        return INodeRegistry(nodeRegistryAddress).getOperator(_pubkey);
    }

    // @inheritdoc IStaderPoolBase
    function getSocializingPoolAddress() external view returns (address) {
        return IPermissionedNodeRegistry(nodeRegistryAddress).elRewardSocializePool();
    }

    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return INodeRegistry(nodeRegistryAddress).isExistingPubkey(_pubkey);
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

    function updateVerifiedKeysBatchSize(uint256 _verifiedKeysBatchSize) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        VERIFIED_KEYS_BATCH_SIZE = _verifiedKeysBatchSize;
    }

    function getCollateralETH() external view override returns (uint256) {
        return INodeRegistry(nodeRegistryAddress).getCollateralETH();
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

    // deposit `PRE_DEPOSIT_SIZE` for validator
    function _preDepositOnBeaconChain(uint256 _validatorId) internal {
        (
            ,
            bytes memory pubkey,
            bytes memory signature,
            address withdrawVaultAddress,
            ,
            ,
            ,

        ) = IPermissionedNodeRegistry(nodeRegistryAddress).validatorRegistry(_validatorId);

        bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVaultAddress
        );
        bytes32 depositDataRoot = this.computeDepositDataRoot(pubkey, signature, withdrawCredential, PRE_DEPOSIT_SIZE);

        //slither-disable-next-line arbitrary-send-eth
        IDepositContract(ethDepositContract).deposit{value: PRE_DEPOSIT_SIZE}(
            pubkey,
            withdrawCredential,
            signature,
            depositDataRoot
        );
        IPermissionedNodeRegistry(nodeRegistryAddress).updateValidatorStatus(pubkey, ValidatorStatus.PRE_DEPOSIT);
        emit ValidatorPreDepositedOnBeaconChain(pubkey);
    }

    // deposit `DEPOSIT_SIZE` for the verified preDeposited Validator
    function _fullDepositOnBeaconChain(bytes calldata _pubkey) internal {
        uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).validatorIdByPubkey(_pubkey);
        (, , bytes memory signature, address withdrawVaultAddress, , , , ) = IPermissionedNodeRegistry(
            nodeRegistryAddress
        ).validatorRegistry(validatorId);
        bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVaultAddress
        );
        bytes32 depositDataRoot = this.computeDepositDataRoot(_pubkey, signature, withdrawCredential, DEPOSIT_SIZE);

        //slither-disable-next-line arbitrary-send-eth
        IDepositContract(ethDepositContract).deposit{value: DEPOSIT_SIZE}(
            _pubkey,
            withdrawCredential,
            signature,
            depositDataRoot
        );
        IPermissionedNodeRegistry(nodeRegistryAddress).setValidatorDepositTime(validatorId);
        emit ValidatorDepositedOnBeaconChain(validatorId, _pubkey);
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
