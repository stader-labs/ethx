// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./interfaces/IRatedV1.sol";

contract RatedV1Mock is IRatedV1 {
    // Storage for validator violations
    mapping(bytes32 => uint256[]) public violations;
    // Storage for validator disputes
    mapping(bytes32 => bool) public disputes;

    constructor() {
    }

    // Implementation of IRatedV1.getViolationsForValidator
    function getViolationsForValidator(bytes32 _pubKeyRoot) external view override returns (uint256[] memory violatedEpochs) {
        return violations[_pubKeyRoot];
    }

    // Implementation of IRatedV1.isValidatorInDispute
    function isValidatorInDispute(bytes32 _pubKeyRoot) external view override returns (bool _isInUnfinishedDispute) {
        return disputes[_pubKeyRoot];
    }
}
