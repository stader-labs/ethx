pragma solidity ^0.8.16;

interface IVaultFactory {
    event WithdrawVaultCreated(address withdrawVault);
    event NodeELRewardVaultCreated(address nodeDistributor);

    function deployWithdrawVault(uint8 poolType, uint256 operatorId, uint256 validatorCount) external returns (address);

    function deployNodeELRewardVault(uint8 poolType, uint256 operatorId, address payable nodeRecipient) external returns (address);

    function computeWithdrawVaultAddress(uint8 poolType, uint256 operatorId, uint256 validatorCount) external view returns (address);

    function computeNodeELRewardVaultAddress(uint8 poolType, uint256 operatorId) external view returns (address);

    function getValidatorWithdrawCredential(address _withdrawVault) external pure returns (bytes memory);
}
