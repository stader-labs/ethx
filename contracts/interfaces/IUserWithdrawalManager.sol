// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IUserWithdrawalManager {
    event WithdrawRequestReceived(
        address _recipient,
        uint256 indexed requestId,
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
    error requestIdNotFinalized(uint256 _requestId);
    error RequestAlreadyRedeemed(uint256 _requestId);
    error InvalidFinalizationRequestId(uint256 _requestId);

    function POOL_MANAGER() external view returns (bytes32);

    function staderOwner() external view returns (address);

    function lockedEtherAmount() external view returns (uint256);

    function nextRequestIdToFinalize() external view returns (uint256);

    function latestRequestId() external view returns (uint256);

    function DECIMAL() external view returns (uint256);

    function userWithdrawRequests(uint256)
        external
        view
        returns (
            bool redeemStatus,
            address payable recipient,
            uint256 ethAmount,
            uint256 ethXAmount,
            uint256 finalizedExchangeRate
        );

    function withdraw(
        address payable _recipient,
        uint256 _ethAmount,
        uint256 _ethXAmount
    ) external returns (uint256);

    function finalize(
        uint256 _finalizeBatchId,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) external payable;

    function redeem(uint256 _requestId) external;
}
