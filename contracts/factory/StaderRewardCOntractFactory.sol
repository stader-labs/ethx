pragma solidity ^0.8.16;

import '../StaderWithdrawVault.sol';
import '../NodeELRewardVault.sol';
import '../interfaces/IStaderRewardContractFactory.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderRewardContractFactory is IStaderRewardContractFactory, Initializable, AccessControlUpgradeable {
    function initialize() external initializer {
        __AccessControl_init_unchained();
    }

    function deployWithdrawVault(
        uint256 operatorId,
        uint256 validatorCount,
        address payable owner
    ) public override returns (address) {
        address withdrawVaultAddress;
        bytes32 salt = sha256(abi.encode(operatorId, validatorCount));
        withdrawVaultAddress = Create2.deploy(0, salt, type(StaderWithdrawVault).creationCode);
        StaderWithdrawVault(payable(withdrawVaultAddress)).initialize(owner);

        emit WithdrawVaultCreated(withdrawVaultAddress);
        return withdrawVaultAddress;
    }

    function deployNodeELRewardVault(uint256 operatorId, address payable nodeRecipient)
        public
        override
        returns (address)
    {
        address nodeELRewardVaultAddress;
        bytes32 salt = sha256(abi.encode(operatorId));
        nodeELRewardVaultAddress = Create2.deploy(0, salt, type(NodeELRewardVault).creationCode);
        NodeELRewardVault(payable(nodeELRewardVaultAddress)).initialize(nodeRecipient);

        emit NodeELRewardVaultCreated(nodeELRewardVaultAddress);
        return nodeELRewardVaultAddress;
    }

    function computeWithdrawVaultAddress(uint256 operatorId, uint256 validatorCount)
        public
        view
        override
        returns (address)
    {
        bytes32 salt = sha256(abi.encode(operatorId, validatorCount));
        return Create2.computeAddress(salt, bytes32(type(StaderWithdrawVault).creationCode));
    }

    function computeNodeELRewardVaultAddress(uint256 operatorId) public view override returns (address) {
        bytes32 salt = sha256(abi.encode(operatorId));
        return Create2.computeAddress(salt, bytes32(type(NodeELRewardVault).creationCode));
    }

    function getValidatorWithdrawCredential(address _withdrawVault) public pure override returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_withdrawVault));
    }
}
