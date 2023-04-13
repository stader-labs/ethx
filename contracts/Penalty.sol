// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IPenalty.sol';
import './interfaces/IRatedV1.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract Penalty is IPenalty, Initializable, AccessControlUpgradeable {
    address public override penaltyOracleAddress;
    uint256 public override maxPenalty;
    uint256 public override onePenalty;
    mapping(bytes32 => uint256) public penaltyReversalAmount;
    mapping(bytes32 => uint256) public additionalPenaltyAmount;

    function initialize(address _penaltyOracleAddress) external initializer {
        __AccessControl_init_unchained();

        penaltyOracleAddress = _penaltyOracleAddress;
        maxPenalty = 4 ether;
        onePenalty = 0.5 ether;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit PenaltyOracleAddressUpdated(_penaltyOracleAddress);
    }

    /// @inheritdoc IPenalty
    function setAdditionalPenaltyAmount(bytes calldata _pubkey, uint256 _amount)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 pubkeyRoot = getPubkeyRoot(_pubkey);
        require(additionalPenaltyAmount[pubkeyRoot] != _amount, 'Penalty: amount is unchanged');

        additionalPenaltyAmount[pubkeyRoot] = _amount;

        emit AdditionalPenaltyAmountUpdated(_pubkey, _amount);
    }

    /// @inheritdoc IPenalty
    function setPenaltyReversalAmount(bytes calldata _pubkey, uint256 _amount)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 pubkeyRoot = getPubkeyRoot(_pubkey);
        require(penaltyReversalAmount[pubkeyRoot] != _amount, 'Penalty: amount is unchanged');

        penaltyReversalAmount[pubkeyRoot] = _amount;

        emit PenaltyReversalAmountUpdated(_pubkey, _amount);
    }

    /// @inheritdoc IPenalty
    function setOnePenalty(uint256 _onePenalty) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(onePenalty != _onePenalty, 'Penalty: one penalty is unchanged');

        onePenalty = _onePenalty;

        emit OnePenaltyUpdated(_onePenalty);
    }

    /// @inheritdoc IPenalty
    function setMaxPenalty(uint256 _maxPenalty) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(maxPenalty != _maxPenalty, 'Penalty: max penalty is unchanged');

        maxPenalty = _maxPenalty;

        emit MaxPenaltyUpdated(_maxPenalty);
    }

    /// @inheritdoc IPenalty
    function setPenaltyOracleAddress(address _penaltyOracleAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_penaltyOracleAddress != address(0), 'Penalty: zero address');

        penaltyOracleAddress = _penaltyOracleAddress;

        emit PenaltyOracleAddressUpdated(_penaltyOracleAddress);
    }

    /// @inheritdoc IPenalty
    function calculatePenalty(bytes calldata _pubkey) external override returns (uint256) {
        // Retrieve the penalty for changing the fee recipient address based on Rated.network data.
        uint256 feeRecipientChangePenalty = calculateFeeRecipientChangePenalty(_pubkey);
        bytes32 pubkeyRoot = getPubkeyRoot(_pubkey);

        // Compute the total penalty for the given validator public key,
        // taking into account additional penalties and penalty reversals from the DAO.
        uint256 totalPenalty = feeRecipientChangePenalty +
            additionalPenaltyAmount[pubkeyRoot] -
            penaltyReversalAmount[pubkeyRoot];

        // Ensure the total penalty does not exceed the maximum penalty.
        if (totalPenalty > maxPenalty) {
            totalPenalty = maxPenalty;
        }

        return totalPenalty;
    }

    /// @inheritdoc IPenalty
    function calculateFeeRecipientChangePenalty(bytes calldata _pubkey) public override returns (uint256) {
        // Retrieve the epochs in which the validator violated the fee recipient change rule.
        uint256[] memory violatedEpochs = IRatedV1(penaltyOracleAddress).getViolatedEpochForValidator(
            getPubkeyRoot(_pubkey)
        );

        return violatedEpochs.length * onePenalty;
    }

    /// @inheritdoc IPenalty
    function getAdditionalPenaltyAmount(bytes calldata _pubkey) external view override returns (uint256) {
        return additionalPenaltyAmount[getPubkeyRoot(_pubkey)];
    }

    /// @inheritdoc IPenalty
    function getPenaltyReversalAmount(bytes calldata _pubkey) external view override returns (uint256) {
        return penaltyReversalAmount[getPubkeyRoot(_pubkey)];
    }

    /// @inheritdoc IPenalty
    function getPubkeyRoot(bytes calldata _pubkey) public pure override returns (bytes32) {
        require(_pubkey.length == 48, 'Invalid pubkey length');

        // Append 16 bytes of zero padding to the pubkey and compute its hash to get the pubkey root.
        return sha256(abi.encodePacked(_pubkey, bytes16(0)));
    }
}
