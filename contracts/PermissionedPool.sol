// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './library/ValidatorStatus.sol';

import './interfaces/IStaderConfig.sol';
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

    IStaderConfig public staderConfig;
    uint8 public constant poolId = 2;

    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    bytes32 public constant PERMISSIONED_POOL_ADMIN = keccak256('PERMISSIONED_POOL_ADMIN');
    bytes32 public constant PERMISSIONED_NODE_REGISTRY = keccak256('PERMISSIONED_NODE_REGISTRY');

    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant FULL_DEPOSIT_SIZE = 31 ether;
    uint256 public constant TOTAL_FEE = 10000;

    // @inheritdoc IStaderPoolBase
    uint256 public override protocolFee;

    // @inheritdoc IStaderPoolBase
    uint256 public override operatorFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    // protection against accidental submissions by calling non-existent function
    receive() external payable {
        revert UnsupportedOperation();
    }

    // protection against accidental submissions by calling non-existent function
    fallback() external payable {
        revert UnsupportedOperation();
    }

    //TODO sanjay Stader Insurance fund to reimburse lost 1 ETH.
    // transfer the 31ETH for defective keys (front run, invalid signature) to stader stake pool manager (SSPM)
    function transferETHOfDefectiveKeysToSSPM(uint256 _defectiveKeyCount)
        external
        onlyRole(PERMISSIONED_NODE_REGISTRY)
    {
        // send back 31 ETH for front run and invalid signature validators back to pool manager
        // These counts are correct because any double reporting of frontrun/invalid statuses results in an error.
        uint256 amountToSendToPoolManager = _defectiveKeyCount * FULL_DEPOSIT_SIZE;
        //slither-disable-next-line arbitrary-send-eth
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveExcessEthFromPool{
            value: amountToSendToPoolManager
        }(poolId);
        emit TransferredETHToSSPMForDefectiveKeys(amountToSendToPoolManager);
    }

    /**
     * @notice receives eth from pool manager to deposit for validators on beacon chain
     * @dev deposit PRE_DEPOSIT_SIZE of ETH for validators while adhering to pool capacity.
     */
    function stakeUserETHToBeaconChain() external payable override onlyRole(POOL_MANAGER) {
        //TODO sanjay how to make sure pool capacity remain same at this point compared to pool selection
        uint256 requiredValidators = msg.value / staderConfig.getStakedEthPerNode();
        address nodeRegistryAddress = staderConfig.getPermissionedNodeRegistry();
        address vaultFactory = staderConfig.getVaultFactory();
        address ethDepositContract = staderConfig.getETHDepositContract();
        uint256[] memory selectedOperatorCapacity = IPermissionedNodeRegistry(nodeRegistryAddress)
            .computeOperatorAllocationForDeposit(requiredValidators);

        // i is the operator Id
        for (uint16 i = 1; i < selectedOperatorCapacity.length; i++) {
            uint256 validatorToDeposit = selectedOperatorCapacity[i];
            if (validatorToDeposit == 0) {
                continue;
            }
            uint256 nextQueuedValidatorIndex = IPermissionedNodeRegistry(nodeRegistryAddress)
                .nextQueuedValidatorIndexByOperatorId(i);

            for (
                uint256 index = nextQueuedValidatorIndex;
                index < nextQueuedValidatorIndex + validatorToDeposit;
                index++
            ) {
                uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).validatorIdsByOperatorId(i, index);
                _preDepositOnBeaconChain(nodeRegistryAddress, vaultFactory, ethDepositContract, validatorId);
            }
            IPermissionedNodeRegistry(nodeRegistryAddress).updateQueuedValidatorIndex(
                i,
                nextQueuedValidatorIndex + validatorToDeposit
            );
        }
        IPermissionedNodeRegistry(nodeRegistryAddress).increaseTotalActiveValidatorCount(requiredValidators);
    }

    // deposit `FULL_DEPOSIT_SIZE` for the verified preDeposited Validator
    function fullDepositOnBeaconChain(bytes[] calldata _pubkey) external onlyRole(PERMISSIONED_NODE_REGISTRY) {
        address nodeRegistryAddress = staderConfig.getPermissionedNodeRegistry();
        address vaultFactory = staderConfig.getVaultFactory();
        address ethDepositContract = staderConfig.getETHDepositContract();
        for (uint256 i = 0; i < _pubkey.length; i++) {
            IPermissionedNodeRegistry(nodeRegistryAddress).onlyPreDepositValidator(_pubkey[i]);
            uint256 validatorId = IPermissionedNodeRegistry(nodeRegistryAddress).validatorIdByPubkey(_pubkey[i]);
            (, , , bytes memory depositSignature, address withdrawVaultAddress, , , ) = INodeRegistry(
                nodeRegistryAddress
            ).validatorRegistry(validatorId);
            bytes memory withdrawCredential = IVaultFactory(vaultFactory).getValidatorWithdrawCredential(
                withdrawVaultAddress
            );
            bytes32 depositDataRoot = this.computeDepositDataRoot(
                _pubkey[i],
                depositSignature,
                withdrawCredential,
                FULL_DEPOSIT_SIZE
            );

            //slither-disable-next-line arbitrary-send-eth
            IDepositContract(ethDepositContract).deposit{value: FULL_DEPOSIT_SIZE}(
                _pubkey[i],
                withdrawCredential,
                depositSignature,
                depositDataRoot
            );
            IPermissionedNodeRegistry(nodeRegistryAddress).updateDepositStatusAndBlock(validatorId);
            emit ValidatorDepositedOnBeaconChain(validatorId, _pubkey[i]);
        }
    }

    /**
     * @notice return total queued keys for permissioned pool
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getTotalQueuedValidatorCount();
    }

    /**
     * @notice return total active keys for permissioned pool
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getTotalActiveValidatorCount();
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
            INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getOperatorTotalNonTerminalKeys(
                _nodeOperator,
                _startIndex,
                _endIndex
            );
    }

    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize)
        public
        view
        override
        returns (Validator[] memory)
    {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getAllActiveValidators(_pageNumber, _pageSize);
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getValidator(_pubkey);
    }

    // @inheritdoc IStaderPoolBase
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getOperator(_pubkey);
    }

    // @inheritdoc IStaderPoolBase
    function getSocializingPoolAddress() external view returns (address) {
        return staderConfig.getPermissionedSocializingPool();
    }

    function getCollateralETH() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).getCollateralETH();
    }

    function getNodeRegistry() external view override returns (address) {
        return staderConfig.getPermissionedNodeRegistry();
    }

    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return INodeRegistry(staderConfig.getPermissionedNodeRegistry()).isExistingPubkey(_pubkey);
    }

    // @inheritdoc IStaderPoolBase
    function setCommissionFees(uint256 _protocolFee, uint256 _operatorFee) external onlyRole(PERMISSIONED_POOL_ADMIN) {
        if (_protocolFee + _operatorFee > TOTAL_FEE) {
            revert CommissionFeesMoreThanTOTAL_FEE();
        }
        if (protocolFee == _protocolFee) {
            revert ProtocolFeeUnchanged();
        }
        if (operatorFee == _operatorFee) {
            revert OperatorFeeUnchanged();
        }

        protocolFee = _protocolFee;
        operatorFee = _operatorFee;

        emit UpdatedCommissionFees(_protocolFee, _operatorFee);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
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
    function _preDepositOnBeaconChain(
        address _nodeRegistryAddress,
        address _vaultFactory,
        address _ethDepositContract,
        uint256 _validatorId
    ) internal {
        (, bytes memory pubkey, bytes memory preDepositSignature, , address withdrawVaultAddress, , , ) = INodeRegistry(
            _nodeRegistryAddress
        ).validatorRegistry(_validatorId);

        bytes memory withdrawCredential = IVaultFactory(_vaultFactory).getValidatorWithdrawCredential(
            withdrawVaultAddress
        );
        bytes32 depositDataRoot = this.computeDepositDataRoot(
            pubkey,
            preDepositSignature,
            withdrawCredential,
            PRE_DEPOSIT_SIZE
        );

        //slither-disable-next-line arbitrary-send-eth
        IDepositContract(_ethDepositContract).deposit{value: PRE_DEPOSIT_SIZE}(
            pubkey,
            withdrawCredential,
            preDepositSignature,
            depositDataRoot
        );
        IPermissionedNodeRegistry(_nodeRegistryAddress).markValidatorStatusAsPreDeposit(pubkey);
        emit ValidatorPreDepositedOnBeaconChain(pubkey);
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
