// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStaderConfig {
    function totalStakedEth() external view returns (uint256);

    function treasury() external view returns (address);

    function stakePoolManager() external view returns (address);
}
