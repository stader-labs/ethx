// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderSSVStakePool {
    event AddedToStaderSSVRegistry(bytes indexed pubKey, uint256 index);
    event DepositToDepositContract(bytes indexed pubKey);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ReceivedETH(address indexed from, uint256 amount);
    event RegisteredValidatorToSSVNetwork(bytes indexed pubKey);
    event RemovedValidatorFromSSVNetwork(bytes indexed pubKey, uint256 index);
    event UpdatedValidatorToSSVNetwork(bytes indexed pubKey, uint256 index);
}
