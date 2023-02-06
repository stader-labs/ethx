pragma solidity ^0.8.16;

interface IStaderELRewardVaultFactory {
    event WithdrawVaultCreated(address withdrawVault);
    event NodeDistributorCreated(address nodeDistributor);

    function deployWithdrawVault(bytes32 salt, address payable owner) external returns (address);

    function deployNodeDistributor(bytes32 salt, address payable nodeRecipient) external returns (address);

    function computeWithdrawVaultAddress(bytes32 salt) external view returns (address);

    function computeNodeDistributorAddress(bytes32 salt) external view returns (address);

    function getValidatorWithdrawCredential(address _withdrawVault) external pure returns (bytes memory);
}
