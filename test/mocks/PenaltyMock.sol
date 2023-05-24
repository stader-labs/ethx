// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract PenaltyMock {
    function markValidatorSettled(uint8, uint256) external {}

    function updateTotalPenaltyAmount(bytes[] calldata) external {}

    function totalPenaltyAmount(bytes calldata) external pure returns (uint256) {
        return 0;
    }
}
