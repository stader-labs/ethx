// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';
import './interfaces/IStaderConfig.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract VaultProxy is Initializable, AccessControlUpgradeable {
    bool isValidatorWithdrawalVault;
    IStaderConfig public staderConfig;

    event UpdatedStaderConfig(address staderConfig);

    function initialize(
        bool _isValidatorWithdrawalVault,
        uint8 _poolId,
        uint256 _Id, //validatorId in case of withdrawVault, operatorId in case of nodeELRewardVault
        address _staderConfig
    ) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();

        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());

        //get the vault implementation form stader config based on vault type
        address vaultImplementation = isValidatorWithdrawalVault
            ? staderConfig.getValidatorWithdrawalVaultImplementation()
            : staderConfig.getNodeELRewardVaultImplementation();
        (bool success, bytes memory data) = vaultImplementation.delegatecall(
            abi.encodeWithSignature('initialise(uint8,uint256,address)', _poolId, _Id, _staderConfig)
        );
        if (!success) {
            revert(string(data));
        }
    }

    fallback(bytes calldata _input) external payable returns (bytes memory) {
        address vaultImplementation = isValidatorWithdrawalVault
            ? staderConfig.getValidatorWithdrawalVaultImplementation()
            : staderConfig.getNodeELRewardVaultImplementation();
        (bool success, bytes memory data) = vaultImplementation.delegatecall(_input);
        if (!success) {
            revert(string(data));
        }
        return data;
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
