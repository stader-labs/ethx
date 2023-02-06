// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract Penalty {
    uint256 public maxPenaltyRate = 0 ether;
    mapping(address => uint256) public reversals;

    // Calculates total MEV penalty
    function calculatePenalty(address _elContractAddress) external returns (uint256) {
        // TODO:
        // 1. Retrieve calculated penalty based on Rated.network data
        // 2. Retrieve reversals (only updatable through multisig/DAO)
        // 3. In future other type of MEV penalties will be introduced
        // 4. Return the overall penalty
        uint256 penalty = calculateFeeRecipientChangePenalty(_elContractAddress);
        return (penalty - getReversals(_elContractAddress));
    }

    function calculateFeeRecipientChangePenalty(address _elContractAddress) public returns (uint256) {
        // TODO: Get penalties from Rated.network contract
        return 0;
    }

    function getReversals(address _elContractAddress) public view returns (uint256) {
        return reversals[_elContractAddress];
    }
}
