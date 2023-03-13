// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/Address.sol';

import '../ValidatorWithdrawVault.sol';
import '../NodeELRewardVault.sol';
import '../interfaces/IVaultFactory.sol';
import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract VaultFactory is IVaultFactory, Initializable, AccessControlUpgradeable {
    address public override vaultOwner;
    address public override poolFactory;
    address payable public override staderTreasury;
    address payable public override staderStakePoolsManager;
    address public nodeELRewardVaultImplementation;
    address public validatorWithdrawVaultImplementation;

    bytes32 public constant override STADER_NETWORK_CONTRACT = keccak256('STADER_NETWORK_CONTRACT');

    function initialize(
        address _factoryAdmin,
        address _vaultOwner,
        address payable _staderTreasury,
        address payable _staderStakePoolsManager,
        address _poolFactory
    ) external initializer {
        Address.checkNonZeroAddress(_factoryAdmin);
        Address.checkNonZeroAddress(_vaultOwner);
        Address.checkNonZeroAddress(_staderTreasury);

        vaultOwner = _vaultOwner;
        staderTreasury = _staderTreasury;
        staderStakePoolsManager = _staderStakePoolsManager;
        poolFactory = _poolFactory;

        __AccessControl_init_unchained();

        nodeELRewardVaultImplementation = address(new NodeELRewardVault());
        validatorWithdrawVaultImplementation = address(new ValidatorWithdrawVault());

        _grantRole(DEFAULT_ADMIN_ROLE, _factoryAdmin);
    }

    function deployWithdrawVault(
        uint8 poolType,
        uint256 operatorId,
        uint256 validatorCount,
        address payable nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address withdrawVaultAddress;
        bytes32 salt = sha256(abi.encode(poolType, operatorId, validatorCount));
        withdrawVaultAddress = ClonesUpgradeable.cloneDeterministic(validatorWithdrawVaultImplementation, salt);
        ValidatorWithdrawVault(payable(withdrawVaultAddress)).initialize(
            vaultOwner,
            nodeRecipient,
            staderTreasury,
            staderStakePoolsManager,
            poolFactory,
            poolType
        );

        emit WithdrawVaultCreated(withdrawVaultAddress);
        return withdrawVaultAddress;
    }

    function deployNodeELRewardVault(
        uint8 poolType,
        uint256 operatorId,
        address payable nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address nodeELRewardVaultAddress;
        bytes32 salt = sha256(abi.encode(poolType, operatorId));
        nodeELRewardVaultAddress = ClonesUpgradeable.cloneDeterministic(nodeELRewardVaultImplementation, salt);
        NodeELRewardVault(payable(nodeELRewardVaultAddress)).initialize(
            vaultOwner,
            nodeRecipient,
            staderTreasury,
            staderStakePoolsManager,
            poolFactory,
            poolType
        );

        emit NodeELRewardVaultCreated(nodeELRewardVaultAddress);
        return nodeELRewardVaultAddress;
    }

    function computeWithdrawVaultAddress(
        uint8 poolType,
        uint256 operatorId,
        uint256 validatorCount
    ) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(poolType, operatorId, validatorCount));
        return ClonesUpgradeable.predictDeterministicAddress(validatorWithdrawVaultImplementation, salt);
    }

    function computeNodeELRewardVaultAddress(uint8 poolType, uint256 operatorId)
        public
        view
        override
        returns (address)
    {
        bytes32 salt = sha256(abi.encode(poolType, operatorId));
        return ClonesUpgradeable.predictDeterministicAddress(nodeELRewardVaultImplementation, salt);
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }
}
