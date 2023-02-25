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
import './interfaces/IPermissionedNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract PermissionedPool is IStaderPoolBase, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using Math for uint256;

    uint8 public constant poolId = 2;
    address public nodeRegistryAddress;
    address public ethDepositContract;
    address public vaultFactoryAddress;
    address public staderStakePoolManager;

    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONED_POOL_ADMIN = keccak256('PERMISSIONED_POOL_ADMIN');
    bytes32 public constant STADER_DAO = keccak256('STADER_DAO');

    uint256 public balanceForDeposit;
    uint256 public nextIndexToDeposit;
    uint256 public MAX_DEPOSIT_BATCH_SIZE;
    uint256 public readyToDepositValidatorSize;
    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant DEPOSIT_SIZE = 31 ether;
    uint256 public constant FULL_DEPOSIT_SIZE = 32 ether;
    uint256 internal constant SIGNATURE_LENGTH = 96;

    /// @inheritdoc IStaderPoolBase
    uint256 public override protocolFeePercent;

    /// @inheritdoc IStaderPoolBase
    uint256 public override operatorFeePercent;

    mapping(uint256 => bytes) public readyToDepositValidator;

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
        __Pausable_init();
        __AccessControl_init_unchained();

        MAX_DEPOSIT_BATCH_SIZE = 100;
        nodeRegistryAddress = _nodeRegistryAddress;
        ethDepositContract = _ethDepositContract;
        vaultFactoryAddress = _vaultFactoryAddress;
        staderStakePoolManager = _staderStakePoolManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    receive() external payable {}

    function markValidatorReadyToDeposit(
        bytes[] calldata _readyToDepositPubkey,
        bytes[] calldata _frontRunPubkey,
        bytes[] calldata _invalidSignaturePubkey
    ) external onlyRole(STADER_DAO) {
        uint256 frontRunValidatorLength = _frontRunPubkey.length;
        uint256 verifiedValidatorLength = _readyToDepositPubkey.length;
        uint256 invalidSignatureValidatorLength = _invalidSignaturePubkey.length;
        if (frontRunValidatorLength > 0) {
            uint256 amountToSendToPoolManager = frontRunValidatorLength * DEPOSIT_SIZE;
            balanceForDeposit -= amountToSendToPoolManager;
            IStaderStakePoolManager(staderStakePoolManager).receiveExcessEthFromPool{value: amountToSendToPoolManager}(
                poolId
            );
            IPermissionedNodeRegistry(nodeRegistryAddress).reportFrontRunValidator(_frontRunPubkey);
        }

        if (invalidSignatureValidatorLength > 0) {
            IPermissionedNodeRegistry(nodeRegistryAddress).reportInvalidSignatureValidator(_invalidSignaturePubkey);
        }

        for (uint256 i = 0; i < verifiedValidatorLength; i++) {
            readyToDepositValidator[readyToDepositValidatorSize] = _readyToDepositPubkey[i];
            readyToDepositValidatorSize++;
        }
    }

    /// @inheritdoc IStaderPoolBase
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        require(_protocolFeePercent <= 100, 'Protocol fee percent should be less than 100');
        require(protocolFeePercent != _protocolFeePercent, 'Protocol fee percent is unchanged');

        protocolFeePercent = _protocolFeePercent;

        emit ProtocolFeePercentUpdated(_protocolFeePercent);
    }

    /// @inheritdoc IStaderPoolBase
    function setOperatorFeePercent(uint256 _operatorFeePercent) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        require(_operatorFeePercent <= 100, 'Operator fee percent should be less than 100');
        require(operatorFeePercent != _operatorFeePercent, 'Operator fee percent is unchanged');

        operatorFeePercent = _operatorFeePercent;

        emit OperatorFeePercentUpdated(_operatorFeePercent);
    }

    /**
     * @notice receives eth from pool Manager to pre deposit validators
     * @dev pre deposit validator taking care of pool capacity
     */
    function registerOnBeaconChain() external payable override onlyRole(POOL_MANAGER) {
        uint256 requiredValidators = msg.value / FULL_DEPOSIT_SIZE;
        uint256[] memory selectedOperatorCapacity = IPermissionedNodeRegistry(nodeRegistryAddress)
            .computeOperatorAllocationForDeposit(requiredValidators);

        /// i is the operator ID
        for (uint256 i = 1; i < selectedOperatorCapacity.length; i++) {
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

                (
                    ,
                    bytes memory pubkey,
                    bytes memory preDepositSignature,
                    ,
                    address withdrawVaultAddress,
                    ,

                ) = IPermissionedNodeRegistry(nodeRegistryAddress).validatorRegistry(validatorId);

                bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                    withdrawVaultAddress
                );
                bytes32 depositDataRoot = _computeDepositDataRoot(
                    pubkey,
                    preDepositSignature,
                    withdrawCredential,
                    PRE_DEPOSIT_SIZE
                );

                //slither-disable-next-line arbitrary-send-eth
                IDepositContract(ethDepositContract).deposit{value: PRE_DEPOSIT_SIZE}(
                    pubkey,
                    withdrawCredential,
                    preDepositSignature,
                    depositDataRoot
                );
                IPermissionedNodeRegistry(nodeRegistryAddress).updateValidatorStatus(
                    pubkey,
                    ValidatorStatus.PRE_DEPOSIT
                );
                emit ValidatorPreDepositedOnBeaconChain(pubkey);
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
     * @notice deposit `DEPOSIT_SIZE` for the processed batch of preDeposited Validator
     * @dev anyone can call, check of available readyToDeposit Validators
     */
    function depositOnBeaconChain() external {
        uint256 count;
        while (nextIndexToDeposit < readyToDepositValidatorSize && count < MAX_DEPOSIT_BATCH_SIZE) {
            bytes memory pubkey = readyToDepositValidator[nextIndexToDeposit];
            uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).validatorIdByPubkey(pubkey);
            (, , , bytes memory depositSignature, address withdrawVaultAddress, , ) = IPermissionedNodeRegistry(
                nodeRegistryAddress
            ).validatorRegistry(validatorId);
            bytes memory withdrawCredential = IVaultFactory(vaultFactoryAddress).getValidatorWithdrawCredential(
                withdrawVaultAddress
            );
            bytes32 depositDataRoot = _computeDepositDataRoot(
                pubkey,
                depositSignature,
                withdrawCredential,
                DEPOSIT_SIZE
            );

            //slither-disable-next-line arbitrary-send-eth
            IDepositContract(ethDepositContract).deposit{value: DEPOSIT_SIZE}(
                pubkey,
                withdrawCredential,
                depositSignature,
                depositDataRoot
            );
            IPermissionedNodeRegistry(nodeRegistryAddress).updateValidatorStatus(pubkey, ValidatorStatus.DEPOSITED);
            count++;
            nextIndexToDeposit++;
            emit ValidatorDepositedOnBeaconChain(validatorId, pubkey);
        }
        balanceForDeposit -= count * DEPOSIT_SIZE;
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

    /// @inheritdoc IStaderPoolBase
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        return INodeRegistry(nodeRegistryAddress).getOperator(_pubkey);
    }

    /// @inheritdoc IStaderPoolBase
    function getSocializingPoolAddress() external view returns (address) {
        return IPermissionedNodeRegistry(nodeRegistryAddress).elRewardSocializePool();
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

    function updateMaxBatchDepositSize(uint256 _batchDepositSize) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        MAX_DEPOSIT_BATCH_SIZE = _batchDepositSize;
    }

    /// @notice calculate the deposit data root based on pubkey, signature, withdrawCredential and amount
    /// formula based on ethereum deposit contract
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
    // copied from https://github.com/lidofinance/lido-dao/blob/df95e563445821988baf9869fde64d86c36be55f/contracts/0.4.24/Lido.sol#L944
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

    ///ethereum deposit contract function to get amount into little_endian_64
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
