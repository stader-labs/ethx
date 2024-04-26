// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IBatchReader {
    function getTotalPenaltyAmounts(bytes[] calldata _pubkeys) external view returns (uint256[] memory);

    function getBalances(address[] calldata _addresses) external view returns (uint256[] memory);
}
