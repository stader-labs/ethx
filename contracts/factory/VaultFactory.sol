// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/Address.sol';

import '../StaderWithdrawVault.sol';
import '../NodeELRewardVault.sol';
import '../interfaces/IVaultFactory.sol';
import '@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract VaultFactory is IVaultFactory, Initializable, AccessControlUpgradeable {
    address public override vaultOwner;
    address payable public override staderTreasury;

    bytes32 public constant override STADER_NETWORK_CONTRACT = keccak256('STADER_NETWORK_CONTRACT');

    function initialize(
        address _factoryAdmin,
        address _vaultOwner,
        address payable _staderTreasury
    ) external initializer {
        Address.checkNonZeroAddress(_factoryAdmin);
        Address.checkNonZeroAddress(_vaultOwner);
        Address.checkNonZeroAddress(_staderTreasury);
        __AccessControl_init_unchained();
        vaultOwner = _vaultOwner;
        staderTreasury = _staderTreasury;
        _grantRole(DEFAULT_ADMIN_ROLE, _factoryAdmin);
    }

    function deployWithdrawVault(
        uint8 poolType,
        uint256 operatorId,
        uint256 validatorCount
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address withdrawVaultAddress;
        bytes32 salt = sha256(abi.encode(poolType, operatorId, validatorCount));
        withdrawVaultAddress = Create2Upgradeable.deploy(0, salt, type(StaderWithdrawVault).creationCode);
        StaderWithdrawVault(payable(withdrawVaultAddress)).initialize(vaultOwner);

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
        nodeELRewardVaultAddress = Create2Upgradeable.deploy(0, salt, type(NodeELRewardVault).creationCode);
        NodeELRewardVault(payable(nodeELRewardVaultAddress)).initialize(vaultOwner, nodeRecipient, staderTreasury);

        emit NodeELRewardVaultCreated(nodeELRewardVaultAddress);
        return nodeELRewardVaultAddress;
    }

    function computeWithdrawVaultAddress(
        uint8 poolType,
        uint256 operatorId,
        uint256 validatorCount
    ) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(poolType, operatorId, validatorCount));
        return Create2Upgradeable.computeAddress(salt, keccak256(type(StaderWithdrawVault).creationCode));
    }

    function computeNodeELRewardVaultAddress(uint8 poolType, uint256 operatorId)
        public
        view
        override
        returns (address)
    {
        bytes32 salt = sha256(abi.encode(poolType, operatorId));
        return Create2Upgradeable.computeAddress(salt, keccak256(type(NodeELRewardVault).creationCode));
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }
}
