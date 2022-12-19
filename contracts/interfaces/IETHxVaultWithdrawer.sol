// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IETHxVaultWithdrawer {
    function receiveVaultWithdrawalETH() external payable;
}
