pragma solidity ^0.8.16;

interface IStaderRewardContractFactory {
    event WithdrawVaultCreated(address withdrawVault);
    event NodeELRewardVaultCreated(address nodeDistributor);

    function deployWithdrawVault(
        uint256 operatorId,
        uint256 validatorCount,
        address payable owner
    ) external returns (address);

    function deployNodeELRewardVault(uint256 operatorId, address payable nodeRecipient) external returns (address);

    function computeWithdrawVaultAddress(uint256 operatorId, uint256 validatorCount) external view returns (address);

    function computeNodeELRewardVaultAddress(uint256 operatorId) external view returns (address);

    function getValidatorWithdrawCredential(address _withdrawVault) external pure returns (bytes memory);
}
