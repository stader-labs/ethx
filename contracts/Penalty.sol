// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IPenalty.sol';
import './interfaces/IRatedV1.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract Penalty is IPenalty, Initializable, AccessControlUpgradeable {
    address public override penaltyOracleAddress;
    uint256 public override maxPenalty;
    uint256 public override onePenalty = 0.5 ether;
    mapping(bytes32 => uint256) public reversals;

    function initialize(address _penaltyOracleAddress) external initializer {
        __AccessControl_init_unchained();

        penaltyOracleAddress = _penaltyOracleAddress;
    }

    // Calculates total MEV penalty
    function calculatePenalty(bytes calldata _pubkey) external override returns (uint256) {
        // TODO:
        // 1. Retrieve calculated penalty based on Rated.network data
        // 2. Retrieve reversals (only updatable through multisig/DAO)
        // 3. In future other type of MEV penalties will be introduced
        // 4. Return the overall penalty
        uint256 penalty = calculateFeeRecipientChangePenalty(_pubkey);
        return (penalty - getReversals(_pubkey));
    }

    function calculateFeeRecipientChangePenalty(bytes calldata _pubkey) public override returns (uint256) {
        uint256[] memory penalties = IRatedV1(penaltyOracleAddress).getViolatedEpochForValidator(
            getPubkeyRoot(_pubkey)
        );
        uint256 totalPenalty = penalties.length * onePenalty;
        if (totalPenalty > maxPenalty) {
            totalPenalty = maxPenalty;
        }
        return totalPenalty;
    }

    function getReversals(bytes calldata _pubkey) public view returns (uint256) {
        return reversals[getPubkeyRoot(_pubkey)];
    }

    function getPubkeyRoot(bytes calldata _pubkey) public pure override returns (bytes32) {
        require(_pubkey.length == 48, 'Invalid pubkey length');

        return sha256(abi.encodePacked(_pubkey, bytes16(0)));
    }
}
