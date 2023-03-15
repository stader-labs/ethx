// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IUserWithdrawalManager {
    error ZeroAddress();
    error TransferFailed();
    error InSufficientBalance();
    error ProtocolNotHealthy();
    error InvalidWithdrawAmount();
    error InvalidMinWithdrawValue();
    error InvalidMaxWithdrawValue();
    error InvalidRequestId(uint256 _requestId);
    error requestIdNotFinalized(uint256 _requestId);
    error RequestAlreadyRedeemed(uint256 _requestId);
    error InvalidFinalizationRequestId(uint256 _requestId);

    event UpdatedMaxWithdrawAmount(uint256 amount);
    event UpdatedMinWithdrawAmount(uint256 amount);
    event UpdatedPaginationLimit(uint256 paginationLimit);
    event WithdrawRequestReceived(
        address indexed _msgSender,
        address _recipient,
        uint256 _requestId,
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

    function USER_WITHDRAWAL_MANAGER_ADMIN() external view returns (bytes32);

    function slashingMode() external view returns (bool);

    function ethX() external view returns (address);

    function poolManager() external view returns (address);

    function minWithdrawAmount() external view returns (uint256);

    function maxWithdrawAmount() external view returns (uint256);

    function paginationLimit() external view returns (uint256);

    function lockedEtherAmount() external view returns (uint256);

    function nextRequestIdToFinalize() external view returns (uint256);

    function latestRequestId() external view returns (uint256);

    function DECIMALS() external view returns (uint256);

    function ethRequestedForWithdraw() external view returns (uint256);

    function userWithdrawRequests(uint256)
        external
        view
        returns (
            bool redeemStatus,
            address owner,
            address payable recipient,
            uint256 ethAmount,
            uint256 ethXAmount,
            uint256 finalizedExchangeRate
        );

    function requestIdsByUserAddress(address, uint256) external view returns (uint256);

    function updateMinWithdrawAmount(uint256 _minWithdrawAmount) external;

    function updateMaxWithdrawAmount(uint256 _minWithdrawAmount) external;

    function updatePaginationLimit(uint256 _paginationLimit) external;

    function withdraw(uint256 _ethXAmount, address receiver) external returns (uint256);

    function finalizeUserWithdrawalRequest() external;

    function redeem(uint256 _requestId) external;
}
