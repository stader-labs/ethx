// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IVaultFactory {
    event WithdrawVaultCreated(address withdrawVault);
    event SSVValidatorWithdrawalVaultCreated(uint256 validatorId, address withdrawVaultAddress);
    event NodeELRewardVaultCreated(address nodeDistributor);
    event UpdatedStaderConfig(address staderConfig);
    event UpdatedVaultProxyImplementation(address vaultProxyImplementation);
    event UpdatedSSVVaultProxyImplementation(address ssvVaultProxyImplementation);

    function NODE_REGISTRY_CONTRACT() external view returns (bytes32);

    function deployWithdrawVault(
        uint8 _poolId,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _validatorId
    ) external returns (address);

    function deploySSVValidatorWithdrawalVault(uint8 _poolId, uint256 _validatorId) external returns (address);

    function deployNodeELRewardVault(uint8 _poolId, uint256 _operatorId) external returns (address);

    function computeWithdrawVaultAddress(
        uint8 _poolId,
        uint256 _operatorId,
        uint256 _validatorCount
    ) external view returns (address);

    function computeSSVValidatorWithdrawalVaultAddress(uint8 _poolId, uint256 _validatorId)
        external
        view
        returns (address);

    function computeNodeELRewardVaultAddress(uint8 _poolId, uint256 _operatorId) external view returns (address);

    function getValidatorWithdrawCredential(address _withdrawVault) external pure returns (bytes memory);

    function updateStaderConfig(address _staderConfig) external;

    function updateVaultProxyAddress(address _vaultProxyImpl) external;

    function updateSSVVaultProxyImplementation(address _ssvVaultProxyImpl) external;
}
