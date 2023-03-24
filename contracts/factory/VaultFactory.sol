// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/Address.sol';

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

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getMultiSigAdmin());
    }

    function deployWithdrawVault(
        uint8 poolId,
        uint256 operatorId,
        uint256 validatorCount,
        address payable nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address withdrawVaultAddress;
        bytes32 salt = sha256(abi.encode(poolId, operatorId, validatorCount));
        withdrawVaultAddress = ClonesUpgradeable.cloneDeterministic(validatorWithdrawalVaultImplementation, salt);
        ValidatorWithdrawalVault(payable(withdrawVaultAddress)).initialize(
            address(staderConfig),
            nodeRecipient,
            poolId
        );

        emit WithdrawVaultCreated(withdrawVaultAddress);
        return withdrawVaultAddress;
    }

    function deployNodeELRewardVault(
        uint8 poolId,
        uint256 operatorId,
        address payable nodeRecipient
    ) public override onlyRole(STADER_NETWORK_CONTRACT) returns (address) {
        address nodeELRewardVaultAddress;
        bytes32 salt = sha256(abi.encode(poolId, operatorId));
        nodeELRewardVaultAddress = ClonesUpgradeable.cloneDeterministic(nodeELRewardVaultImplementation, salt);
        NodeELRewardVault(payable(nodeELRewardVaultAddress)).initialize(address(staderConfig), nodeRecipient, poolId);

        emit NodeELRewardVaultCreated(nodeELRewardVaultAddress);
        return nodeELRewardVaultAddress;
    }

    function computeWithdrawVaultAddress(
        uint8 poolId,
        uint256 operatorId,
        uint256 validatorCount
    ) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(poolId, operatorId, validatorCount));
        return ClonesUpgradeable.predictDeterministicAddress(validatorWithdrawalVaultImplementation, salt);
    }

    // TODO change it to poolID
    function computeNodeELRewardVaultAddress(uint8 poolId, uint256 operatorId) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(poolId, operatorId));
        return ClonesUpgradeable.predictDeterministicAddress(nodeELRewardVaultImplementation, salt);
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }

    //update the address of staderConfig
    //TODO sanjay double check on this role
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
    }
}
