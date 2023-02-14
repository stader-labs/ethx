// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISDStaking {
    function getExchangeRate() external view returns (uint256);
}
