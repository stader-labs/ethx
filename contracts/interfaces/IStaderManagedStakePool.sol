// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IStaderManagedStakePool {
    event DepositToDepositContract(bytes indexed pubKey);
    event ReceivedETH(address indexed from, uint256 amount);
}
