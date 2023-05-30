// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract PenaltyMockForVault {
    mapping(bytes => uint256) public totalPenaltyAmount;

    function markValidatorSettled(uint8, uint256) external {}

    function updateTotalPenaltyAmount(bytes[] calldata pubkeys) external {
        uint256 len = pubkeys.length;

        for (uint256 i = 0; i < len; i++) {
            totalPenaltyAmount[pubkeys[i]] = 10 ether;
        }
    }
}
