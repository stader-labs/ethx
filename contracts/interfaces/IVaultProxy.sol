pragma solidity ^0.8.16;

import './IStaderConfig.sol';

interface IVaultProxy {
    error CallerNotOwner();
    event UpdatedOwner(address owner);
    event UpdatedStaderConfig(address staderConfig);

    //Getters
    function vaultSettleStatus() external view returns (bool);

    function isValidatorWithdrawalVault() external view returns (bool);

    function poolId() external view returns (uint8);

    function id() external view returns (uint256);

    function owner() external view returns (address);

    function staderConfig() external view returns (IStaderConfig);

    //Setters
    function updateOwner(address _owner) external;

    function updateStaderConfig(address _staderConfig) external;
}
