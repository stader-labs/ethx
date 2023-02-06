// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderUserWithdrawalManager {
    event WithdrawRequestReceived(
        address indexed _sender,
        address _recipient,
        uint256 _sharesAmount,
        uint256 _etherAmount
    );
    event RequestRedeemed(address indexed _sender, address _recipient, uint256 _ethTransferred);
    event RecipientAddressUpdated(
        address indexed _sender,
        uint256 _requestId,
        address _oldRecipient,
        address _newRecipient
    );

    error ZeroAddress();
    error TransferFailed();
    error InSufficientBalance();
    error InvalidRequestId(uint256 _requestId);
    error RequestNotFinalized(uint256 _requestId);
    error InvalidLastFinalizationBatch(uint256 _requestId);
    error BatchNotFinalized(uint256 _batchNumber, uint256 _requestId);
    error IdenticalRecipientAddressProvided(address _sender, address _recipient, uint256 _requestId);

    function POOL_MANAGER() external view returns (bytes32);

    function poolManager() external view returns (address);

    function lockedEtherAmount() external view returns (uint256);

    function latestRequestId() external view returns (uint256);

    function lastFinalizedBatch() external view returns (uint256);

    function currentBatchNumber() external view returns (uint256);

    function DECIMAL() external view returns (uint256);

    function requiredBatchEThThreshold() external view returns (uint256);

    function batchRequest(uint256)
        external
        view
        returns (
            bool finalized,
            uint256 startTime,
            uint256 finalizedExchangeRate,
            uint256 requiredEth,
            uint256 lockedEthX
        );

    function withdraw(
        address msgSender,
        address payable _recipient,
        uint256 _ethAmount,
        uint256 _ethXAmount
    ) external;

    function finalize(
        uint256 _finalizedBatchNumber,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) external payable;

    function redeem(uint256 _requestId) external;

    function changeRecipient(uint256 _requestId, address _newRecipient) external;
}
