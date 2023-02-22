// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

// Interface for the Penalty contract
interface IPenalty {
    // Events
    event AdditionalPenaltyAmountUpdated(bytes indexed pubkey, uint256 amount);
    event PenaltyReversalAmountUpdated(bytes indexed pubkey, uint256 amount);
    event OnePenaltyUpdated(uint256 onePenalty);
    event MaxPenaltyUpdated(uint256 maxPenalty);
    event PenaltyOracleAddressUpdated(address penaltyOracleAddress);

    // returns the address of the Rated.network penalty oracle
    function penaltyOracleAddress() external view returns (address);

    // returns the maximum penalty amount
    function maxPenalty() external view returns (uint256);

    // returns the penalty amount for a single violation
    function onePenalty() external view returns (uint256);

    // Setters

    // Sets the address of the Rated.network penalty oracle.
    function setPenaltyOracleAddress(address _penaltyOracleAddress) external;

    // Sets the maximum penalty amount. This is the highest possible penalty that can be imposed.
    function setMaxPenalty(uint256 _maxPenalty) external;

    // Sets the penalty amount for a single violation. This is the amount that will be imposed for each violation of the contract.
    function setOnePenalty(uint256 _onePenalty) external;

    /**
     * @notice Sets the additional penalty amount given by the DAO for a given validator public key.
     * @param _pubkey The validator public key for which to set the additional penalty amount.
     * @param _amount The additional penalty amount to set for the given validator public key.
     */
    function setAdditionalPenaltyAmount(bytes calldata _pubkey, uint256 _amount) external;

    /**
     * @notice Sets the penalty reversal amount given by the DAO for a given validator public key.
     * @param _pubkey The validator public key for which to set the penalty reversal amount.
     * @param _amount The penalty reversal amount to set for the given validator public key.
     */
    function setPenaltyReversalAmount(bytes calldata _pubkey, uint256 _amount) external;

    // Getters

    // Returns the additional penalty amount given by the DAO for a given public key.
    function getAdditionalPenaltyAmount(bytes calldata _pubkey) external view returns (uint256);

    // Returns the penalty reversal amount given by the DAO for a given public key.
    function getPenaltyReversalAmount(bytes calldata _pubkey) external view returns (uint256);

    /**
     * @notice Computes the public key root.
     * @param _pubkey The validator public key for which to compute the root.
     * @return The root of the public key.
     */
    function getPubkeyRoot(bytes calldata _pubkey) external pure returns (bytes32);

    /**
     * @notice Calculates the total MEV penalty for a given public key.
     * @param _pubkey The public key of the validator for which to calculate the penalty.
     * @return The total MEV penalty.
     */
    function calculatePenalty(bytes calldata _pubkey) external returns (uint256);

    /**
     * @notice Calculates the penalty for changing the fee recipient address for a given public key
     *         based on data from the Rated.network penalty oracle.
     * @param _pubkey The public key for which to calculate the penalty.
     * @return The penalty for changing the fee recipient address.
     */
    function calculateFeeRecipientChangePenalty(bytes calldata _pubkey) external returns (uint256);
}
