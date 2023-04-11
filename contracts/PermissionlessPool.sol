// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionlessPool is IStaderPoolBase, Initializable, AccessControlUpgradeable {
    using Math for uint256;
    uint8 public constant poolId = 1;
    IStaderConfig public staderConfig;

    uint256 public constant DEPOSIT_NODE_BOND = 3 ether;
    uint256 public constant PRE_DEPOSIT_SIZE = 1 ether;
    uint256 public constant FULL_DEPOSIT_SIZE = 31 ether;
    uint256 public constant TOTAL_FEE = 10000;

    /// @inheritdoc IStaderPoolBase
    uint256 public override protocolFee;

    /// @inheritdoc IStaderPoolBase
    uint256 public override operatorFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
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

    // receive `DEPOSIT_NODE_BOND` collateral ETH from permissionless node registry
    function receiveRemainingCollateralETH() external payable {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.PERMISSIONLESS_NODE_REGISTRY());
        emit ReceivedCollateralETH(msg.value);
    }

    /// @inheritdoc IStaderPoolBase
    function setCommissionFees(uint256 _protocolFee, uint256 _operatorFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /**
     * @notice pre deposit for permission less validator to avoid front running
     * @dev only permissionless node registry can call
     * @param _pubkey pubkey array of validators
     * @param _preDepositSignature signature array of validators for 1ETH deposit
     * @param _operatorId operator Id of the NO
     * @param _operatorTotalKeys total keys of operator at the starting of adding new keys
     */
    function preDepositOnBeaconChain(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        uint256 _operatorId,
        uint256 _operatorTotalKeys
    ) external payable {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.PERMISSIONLESS_NODE_REGISTRY());
        address vaultFactory = staderConfig.getVaultFactory();
        for (uint256 i = 0; i < _pubkey.length; i++) {
            address withdrawVault = IVaultFactory(vaultFactory).computeWithdrawVaultAddress(
                poolId,
                _operatorId,
                _operatorTotalKeys + i
            );
            bytes memory withdrawCredential = IVaultFactory(vaultFactory).getValidatorWithdrawCredential(withdrawVault);

            bytes32 depositDataRoot = this.computeDepositDataRoot(
                _pubkey[i],
                _preDepositSignature[i],
                withdrawCredential,
                PRE_DEPOSIT_SIZE
            );
            //slither-disable-next-line arbitrary-send-eth
            IDepositContract(staderConfig.getETHDepositContract()).deposit{value: PRE_DEPOSIT_SIZE}(
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
    function stakeUserETHToBeaconChain() external payable override {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STAKE_POOL_MANAGER());
        uint256 requiredValidators = msg.value / (FULL_DEPOSIT_SIZE - DEPOSIT_NODE_BOND);
        address nodeRegistryAddress = staderConfig.getPermissionlessNodeRegistry();
        IPermissionlessNodeRegistry(nodeRegistryAddress).transferCollateralToPool(
            requiredValidators * DEPOSIT_NODE_BOND
        );

        address vaultFactoryAddress = staderConfig.getVaultFactory();
        address ethDepositContract = staderConfig.getETHDepositContract();
        uint256 depositQueueStartIndex = IPermissionlessNodeRegistry(nodeRegistryAddress).nextQueuedValidatorIndex();
        for (uint256 i = depositQueueStartIndex; i < requiredValidators + depositQueueStartIndex; i++) {
            uint256 validatorId = IPermissionlessNodeRegistry(nodeRegistryAddress).queuedValidators(i);
            fullDepositOnBeaconChain(
                nodeRegistryAddress,
                vaultFactoryAddress,
                ethDepositContract,
                validatorId,
                FULL_DEPOSIT_SIZE
            );
        }
        IPermissionlessNodeRegistry(nodeRegistryAddress).updateNextQueuedValidatorIndex(
            depositQueueStartIndex + requiredValidators
        );
        IPermissionlessNodeRegistry(nodeRegistryAddress).increaseTotalActiveValidatorCount(requiredValidators);
        // balance must be 0 at this point
        assert(address(this).balance == 0);
    }

    // @inheritdoc IStaderPoolBase
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getOperator(_pubkey);
    }

    /// @inheritdoc IStaderPoolBase
    function getSocializingPoolAddress() external view returns (address) {
        return staderConfig.getPermissionlessSocializingPool();
    }

    /**
     * @notice return total queued keys for permissionless pool
     */
    function getTotalQueuedValidatorCount() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getTotalQueuedValidatorCount();
    }

    /**
     * @notice return total active keys for permissionless pool
     */
    function getTotalActiveValidatorCount() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getTotalActiveValidatorCount();
    }

    /**
     * @notice get all validator which has user balance on beacon chain
     */
    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize)
        external
        view
        override
        returns (Validator[] memory)
    {
        return
            INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getAllActiveValidators(_pageNumber, _pageSize);
    }

    // returns array of nodeELRewardVault address for opt out of socializing pool operators
    function getAllSocializingPoolOptOutOperators(uint256 _pageNumber, uint256 _pageSize)
        external
        view
        returns (address[] memory)
    {
        return
            IPermissionlessNodeRegistry(staderConfig.getPermissionlessNodeRegistry())
                .getAllSocializingPoolOptOutOperators(_pageNumber, _pageSize);
    }

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getValidator(_pubkey);
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
            INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getOperatorTotalNonTerminalKeys(
                _nodeOperator,
                _startIndex,
                _endIndex
            );
    }

    function getCollateralETH() external view override returns (uint256) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).getCollateralETH();
    }

    function getNodeRegistry() external view override returns (address) {
        return staderConfig.getPermissionlessNodeRegistry();
    }

    // check for duplicate keys in permissionless pool
    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).isExistingPubkey(_pubkey);
    }

    // check for duplicate operator in permissionless pool
    function isExistingOperator(address _operAddr) external view override returns (bool) {
        return INodeRegistry(staderConfig.getPermissionlessNodeRegistry()).isExistingOperator(_operAddr);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
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

    function fullDepositOnBeaconChain(
        address _nodeRegistryAddress,
        address _vaultFactoryAddress,
        address _ethDepositContract,
        uint256 _validatorId,
        uint256 _DEPOSIT_SIZE
    ) internal {
        (, bytes memory pubkey, , bytes memory depositSignature, address withdrawVaultAddress, , , ) = INodeRegistry(
            _nodeRegistryAddress
        ).validatorRegistry(_validatorId);

        bytes memory withdrawCredential = IVaultFactory(_vaultFactoryAddress).getValidatorWithdrawCredential(
            withdrawVaultAddress
        );

        bytes32 depositDataRoot = this.computeDepositDataRoot(
            pubkey,
            depositSignature,
            withdrawCredential,
            _DEPOSIT_SIZE
        );
        IDepositContract(_ethDepositContract).deposit{value: _DEPOSIT_SIZE}(
            pubkey,
            withdrawCredential,
            depositSignature,
            depositDataRoot
        );
        IPermissionlessNodeRegistry(_nodeRegistryAddress).updateDepositStatusAndBlock(_validatorId);
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

    // modifier onlyPermissionlessNodeRegistry() {
    //     if (msg.sender != staderConfig.getPermissionlessNodeRegistry()) {
    //         revert CallerNotPermissionlessNodeRegistry();
    //     }
    //     _;
    // }
}
