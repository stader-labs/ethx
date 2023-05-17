// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IStaderConfig.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract VaultProxy is Initializable, AccessControlUpgradeable {
    address vaultImplementation;
    IStaderConfig public staderConfig;

    event ETHReceived(address indexed sender, uint256 amount);

    function initialize(
        uint8 _poolId,
        uint256 _Id, //validatorId in case of withdrawVault, operatorId in case of nodeELRewardVault
        address _staderConfig,
        address _vaultImplementation //implementation of withdrawVault or nodeELRewardVault
    ) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init_unchained();

        staderConfig = IStaderConfig(_staderConfig);
        vaultImplementation = _vaultImplementation;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
        (bool success, bytes memory data) = vaultImplementation.delegatecall(
            abi.encodeWithSignature('initialise(uint8,uint256,address)', _poolId, _Id, _staderConfig)
        );
        // if (!success) { revert(getRevertMessage(data)); }
    }

    // Allows the contract to receive ETH
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    fallback(bytes calldata _input) external payable returns (bytes memory) {
        // If useLatestDelegate is set, use the latest delegate contract
        // address delegateContract = useLatestDelegate ? getContractAddress("rocketMinipoolDelegate") : rocketMinipoolDelegate;
        // Check for contract existence
        // require(contractExists(vaultImplementation), "Delegate contract does not exist");
        // Execute delegatecall
        (bool success, bytes memory data) = vaultImplementation.delegatecall(_input);
        // if (!success) { revert(getRevertMessage(data)); }
        return data;
    }
}
