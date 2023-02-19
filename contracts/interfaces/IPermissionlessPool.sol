pragma solidity ^0.8.16;

interface IPermissionlessPool {
    function preDepositOnBeacon(
        bytes calldata _pubkey,
        bytes calldata _signature,
        address withdrawVault
    ) external payable;
}
