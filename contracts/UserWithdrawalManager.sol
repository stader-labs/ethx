// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract UserWithdrawalManager is IUserWithdrawalManager, Initializable, AccessControlUpgradeable {
    bytes32 public constant override POOL_MANAGER = keccak256('POOL_MANAGER');

    address public override staderOwner;

    uint256 public constant override DECIMAL = 10**18;

    uint256 public override lockedEtherAmount;

    uint256 public override nextRequestIdToFinalize;

    uint256 public override latestRequestId;

    /// @notice user withdrawal requests
    mapping(uint256 => UserWithdrawInfo) public override userWithdrawRequests;

    /// @notice structure representing a user request for withdrawal.
    struct UserWithdrawInfo {
        bool redeemStatus; //withdraw request redeemed if variable is true
        address payable recipient; //payable address of the recipient to transfer withdrawal
        uint256 ethAmount; //eth requested according to given share and exchangeRate
        uint256 ethXAmount; //amount of ethX share locked for withdrawal
        uint256 finalizedExchangeRate; // exchange rate at which withdraw request is finalized
    }

    function initialize(address _staderOwner) external initializer {
        if (_staderOwner == address(0)) revert ZeroAddress();
        __AccessControl_init_unchained();
        staderOwner = _staderOwner;
        nextRequestIdToFinalize = 1;
        latestRequestId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice put a withdrawal request and assign it to a batch
     * @param _recipient withdraw address for user to get back eth
     * @param _ethAmount eth amount to be send at the withdraw exchange rate
     * @param _ethXAmount amount of ethX shares that will be burned upon withdrawal
     */
    function withdraw(
        address payable _recipient,
        uint256 _ethAmount,
        uint256 _ethXAmount
    ) external override onlyRole(POOL_MANAGER) returns (uint256) {
        userWithdrawRequests[latestRequestId] = UserWithdrawInfo(
            false,
            payable(_recipient),
            _ethAmount,
            _ethXAmount,
            0
        );
        latestRequestId++;
        emit WithdrawRequestReceived(_recipient, latestRequestId - 1, _ethXAmount, _ethAmount);
        return latestRequestId - 1;
    }

    /**
     * @notice Finalize the batch from `lastFinalizedBatch` to _finalizedBatchNumber at `_finalizedExchangeRate`
     * @param _finalizeRequestId request ID to finalize up to from nextRequestIdToFinalize
     * @param _ethToLock ether that should be locked for these requests
     * @param _finalizedExchangeRate finalized exchangeRate
     */
    function finalize(
        uint256 _finalizeRequestId,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) external payable override onlyRole(POOL_MANAGER) {
        if (_finalizeRequestId < nextRequestIdToFinalize || _finalizeRequestId >= latestRequestId)
            revert InvalidFinalizationRequestId(_finalizeRequestId);
        if (lockedEtherAmount + _ethToLock > address(this).balance) revert InSufficientBalance();

        for (uint256 i = nextRequestIdToFinalize; i <= _finalizeRequestId; i++) {
            userWithdrawRequests[i].finalizedExchangeRate = _finalizedExchangeRate;
        }
        lockedEtherAmount += _ethToLock;
        nextRequestIdToFinalize = _finalizeRequestId + 1;
    }

    /**
     * @notice transfer the eth of finalized request and delete the request
     * @param _requestId request id to redeem
     */
    function redeem(uint256 _requestId) external override {
        if (_requestId >= latestRequestId) revert InvalidRequestId(_requestId);
        if (_requestId >= nextRequestIdToFinalize) revert requestIdNotFinalized(_requestId);
        UserWithdrawInfo memory userRequest = userWithdrawRequests[_requestId];
        if (userRequest.redeemStatus) revert RequestAlreadyRedeemed(_requestId);

        uint256 ethXAmount = userRequest.ethXAmount;
        uint256 ethAmount = userRequest.ethAmount;

        uint256 etherToTransfer = _min((ethXAmount * userRequest.finalizedExchangeRate) / DECIMAL, ethAmount);
        lockedEtherAmount -= etherToTransfer;
        _sendValue(userRequest.recipient, etherToTransfer);

        emit RequestRedeemed(msg.sender, userRequest.recipient, etherToTransfer);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InSufficientBalance();

        // solhint-disable-next-line
        (bool success, ) = recipient.call{value: amount}('');
        if (!success) revert TransferFailed();
    }
}
