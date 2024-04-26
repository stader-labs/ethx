// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import "./interfaces/IPenalty.sol";
import "./interfaces/IStaderConfig.sol";
import "./interfaces/IBatchReader.sol";

/// @title Batch Reader Contract
/// @notice Provides batch operations for reading penalties and balances
contract BatchReader is IBatchReader {
    IPenalty public immutable PENALTY_CONTRACT;

    /// @param _staderConfig Address of the StaderConfig contract
    constructor(address _staderConfig) {
        require(_staderConfig != address(0), "BatchReader: invalid StaderConfig address");

        PENALTY_CONTRACT = IPenalty(IStaderConfig(_staderConfig).getPenaltyContract());
    }

    /// @notice Reads the total penalty amounts for a batch of validators
    /// @param _pubkeys Public keys of the validators
    /// @return penalties Array of total penalty amounts for each validator
    function getTotalPenaltyAmounts(bytes[] calldata _pubkeys) external view override returns (uint256[] memory penalties) {
        penalties = new uint256[](_pubkeys.length);
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            penalties[i] = PENALTY_CONTRACT.totalPenaltyAmount(_pubkeys[i]);
        }
    }

    /// @notice Gets balances for multiple addresses
    /// @param _addresses Array of Ethereum addresses
    /// @return balances Array of balances for the provided addresses
    function getBalances(address[] calldata _addresses) external view override returns (uint256[] memory balances) {
        balances = new uint256[](_addresses.length);
        for (uint256 i = 0; i < _addresses.length; i++) {
            balances[i] = _addresses[i].balance;
        }
    }
}
