// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

// Interface for the NodeRegistry contract
interface INodeRegistry {
    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all operators

    function getTotalInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getTotalWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all operators
}
