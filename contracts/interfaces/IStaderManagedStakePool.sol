// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderManagedStakePool {
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
}
