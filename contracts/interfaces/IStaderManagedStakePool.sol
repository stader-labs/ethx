// File: contracts/interfaces/IStaderSSVStakePool.sol
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

interface IStaderManagedStakePool {
    event Initialized(uint8 version);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ReceivedFromPoolManager(address indexed from, uint256 amout);

    function initialize() external;

    function owner() external view returns (address);

    function receiveEthFromPoolManager() external payable;

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;
}
