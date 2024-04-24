// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./interfaces/IPenalty.sol";
import "./interfaces/IStaderConfig.sol";
import "./interfaces/IBatchReader.sol";

contract BatchReader is IBatchReader {
    IPenalty public penaltyContract;
    IStaderConfig immutable staderConfig;

    constructor(address _staderConfig) {
        require(_staderConfig != address(0), "Invalid StaderConfig address");

        staderConfig = IStaderConfig(_staderConfig);
        penaltyContract = IPenalty(staderConfig.getPenaltyContract());
    }

    /// @notice Reads the total penalty amounts for a batch of validators.
    function getTotalPenaltyAmounts(bytes[] calldata _pubkeys) external view override returns (uint256[] memory) {
        uint256[] memory penalties = new uint256[](_pubkeys.length);
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            penalties[i] = penaltyContract.totalPenaltyAmount(_pubkeys[i]);
        }
        return penalties;
    }
}
