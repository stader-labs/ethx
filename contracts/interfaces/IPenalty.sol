// Interface for the Penalty contract
interface IPenalty {
    function penaltyOracleAddress() external view returns (address);

    function maxPenalty() external view returns (uint256);

    function onePenalty() external view returns (uint256);

    function getPubkeyRoot(bytes calldata _pubkey) external pure returns (bytes32);

    function calculatePenalty(bytes calldata _pubkey) external returns (uint256);

    function calculateFeeRecipientChangePenalty(bytes calldata _pubkey) external returns (uint256);
}
