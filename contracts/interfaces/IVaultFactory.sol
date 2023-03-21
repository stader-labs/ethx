// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IVaultFactory {
    event WithdrawVaultCreated(address withdrawVault);
    event NodeELRewardVaultCreated(address nodeDistributor);

    function vaultOwner() external view returns (address);

    function staderTreasury() external view returns (address payable);

    function staderStakePoolsManager() external view returns (address payable);

    function poolFactory() external view returns (address);

    function STADER_NETWORK_CONTRACT() external view returns (bytes32);

    function deployWithdrawVault(
        uint8 poolId,
        uint256 operatorId,
        uint256 validatorCount,
        address payable nodeRecipient
    ) external returns (address);

    function deployNodeELRewardVault(
        uint8 poolId,
        uint256 operatorId,
        address staderConfig,
        address payable nodeRecipient
    ) external returns (address);

    function computeWithdrawVaultAddress(
        uint8 poolId,
        uint256 operatorId,
        uint256 validatorCount
    ) external view returns (address);

    function computeNodeELRewardVaultAddress(uint8 poolId, uint256 operatorId) external view returns (address);

    function getValidatorWithdrawCredential(address _withdrawVault) external pure returns (bytes memory);
}
