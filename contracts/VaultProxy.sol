// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';
import 'forge-std/Test.sol';

import './interfaces/IVaultProxy.sol';

//contract to delegate call to respective vault implementation based on the flag of 'isValidatorWithdrawalVault'
contract VaultProxy is IVaultProxy {
    bool public override vaultSettleStatus;
    bool public override isValidatorWithdrawalVault;
    uint8 public override poolId;
    uint256 public override id; //validatorId or operatorId based on vault type
    address public override owner;
    IStaderConfig public override staderConfig;

    constructor() {}

    //TODO do we need to put some check to avoid call from unwanted address?
    function initialise(
        bool _isValidatorWithdrawalVault,
        uint8 _poolId,
        uint256 _id,
        address _staderConfig
    ) external {
        UtilLib.checkNonZeroAddress(_staderConfig);
        isValidatorWithdrawalVault = _isValidatorWithdrawalVault;
        poolId = _poolId;
        id = _id;
        staderConfig = IStaderConfig(_staderConfig);
        owner = staderConfig.getAdmin();
    }

    /**route all call to this proxy contract to the respective latest vault contract
     * fetched from staderConfig. This approch will help in changing the implementation
     * of validatorWithdrawalVault/nodeELRewardVault for already deployed vaults*/
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
    function updateStaderConfig(address _staderConfig) external override onlyOwner {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function updateOwner(address _owner) external override onlyOwner {
        UtilLib.checkNonZeroAddress(_owner);
        owner = _owner;
        emit UpdatedOwner(owner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CallerNotOwner();
        }
        _;
    }
}
