// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

// Interface for the NodeRegistry contract
interface INodeRegistry {
    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators
}
