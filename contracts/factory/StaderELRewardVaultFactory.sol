pragma solidity ^0.8.16;

import '../StaderWithdrawVault.sol';
import '../StaderNodeDistributor.sol';
import '../interfaces/IStaderELRewardVaultFactory.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderELRewardVaultFactory is IStaderELRewardVaultFactory, Initializable, AccessControlUpgradeable {
    function initialize() external initializer {
        __AccessControl_init_unchained();
    }

    function deployWithdrawVault(bytes32 salt, address payable owner) public override returns (address) {
        address withdrawVaultAddress;

        withdrawVaultAddress = Create2.deploy(0, salt, type(StaderWithdrawVault).creationCode);
        StaderWithdrawVault(payable(withdrawVaultAddress)).initialize(owner);

        emit WithdrawVaultCreated(withdrawVaultAddress);
        return withdrawVaultAddress;
    }

    function deployNodeDistributor(bytes32 salt, address payable nodeRecipient) public override returns (address) {
        address nodeDistributorAddress;

        nodeDistributorAddress = Create2.deploy(0, salt, type(StaderNodeDistributor).creationCode);
        StaderNodeDistributor(payable(nodeDistributorAddress)).initialize(nodeRecipient);

        emit NodeDistributorCreated(nodeDistributorAddress);
        return nodeDistributorAddress;
    }

    function computeWithdrawVaultAddress(bytes32 salt) public view override returns (address) {
        return Create2.computeAddress(salt, bytes32(type(StaderWithdrawVault).creationCode));
    }

    function computeNodeDistributorAddress(bytes32 salt) public view override returns (address) {
        return Create2.computeAddress(salt, bytes32(type(StaderNodeDistributor).creationCode));
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }
}
