// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/AddressLib.sol';

import '../ValidatorWithdrawalVault.sol';
import '../NodeELRewardVault.sol';

import '../interfaces/IVaultFactory.sol';
import '../interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract VaultFactory is IVaultFactory, Initializable, AccessControlUpgradeable {
    IStaderConfig public staderConfig;
    address public nodeELRewardVaultImplementation;
    address public validatorWithdrawalVaultImplementation;

    bytes32 public constant override STADER_NETWORK_CONTRACT = keccak256('STADER_NETWORK_CONTRACT');

    function initialize(address _staderConfig) external initializer {
        __AccessControl_init_unchained();

        staderConfig = IStaderConfig(_staderConfig);
        nodeELRewardVaultImplementation = address(new NodeELRewardVault());
        validatorWithdrawalVaultImplementation = address(new ValidatorWithdrawalVault());

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    function deployWithdrawVault(
        uint8 _poolId,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _validatorId,
        address payable _nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address withdrawVaultAddress;
        bytes32 salt = sha256(abi.encode(_poolId, _operatorId, _validatorCount));
        withdrawVaultAddress = ClonesUpgradeable.cloneDeterministic(validatorWithdrawalVaultImplementation, salt);
        ValidatorWithdrawalVault(payable(withdrawVaultAddress)).initialize(
            _poolId,
            address(staderConfig),
            _nodeRecipient,
            _validatorId
        );

        emit WithdrawVaultCreated(withdrawVaultAddress);
        return withdrawVaultAddress;
    }

    function deployNodeELRewardVault(
        uint8 _poolId,
        uint256 _operatorId,
        address payable _nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address nodeELRewardVaultAddress;
        bytes32 salt = sha256(abi.encode(_poolId, _operatorId));
        nodeELRewardVaultAddress = ClonesUpgradeable.cloneDeterministic(nodeELRewardVaultImplementation, salt);
        NodeELRewardVault(payable(nodeELRewardVaultAddress)).initialize(address(staderConfig), _nodeRecipient, _poolId);

        emit NodeELRewardVaultCreated(nodeELRewardVaultAddress);
        return nodeELRewardVaultAddress;
    }

    function computeWithdrawVaultAddress(
        uint8 _poolId,
        uint256 _operatorId,
        uint256 _validatorCount
    ) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(_poolId, _operatorId, _validatorCount));
        return ClonesUpgradeable.predictDeterministicAddress(validatorWithdrawalVaultImplementation, salt);
    }

    // TODO change it to poolID
    function computeNodeELRewardVaultAddress(uint8 _poolId, uint256 _operatorId)
        public
        view
        override
        returns (address)
    {
        bytes32 salt = sha256(abi.encode(_poolId, _operatorId));
        return ClonesUpgradeable.predictDeterministicAddress(nodeELRewardVaultImplementation, salt);
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
