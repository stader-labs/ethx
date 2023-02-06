pragma solidity ^0.8.16;

import './interfaces/IStaderUserWithdrawalManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderUserWithdrawalManager is IStaderUserWithdrawalManager, Initializable, AccessControlUpgradeable {
    bytes32 public constant override POOL_MANAGER = keccak256('POOL_MANAGER');

    address public override poolManager;

    uint256 public constant override DECIMAL = 10**18;

    uint256 public override lockedEtherAmount;

    uint256 public override latestRequestId;

    uint256 public override lastFinalizedBatch;

    uint256 public override currentBatchNumber;

    uint256 public override requiredBatchEThThreshold;

    /// @notice user withdrawal requests
    mapping(address => UserWithdrawInfo[]) public userWithdrawRequests;

    mapping(uint256 => BatchInfo) public override batchRequest;

    /// @notice structure representing a user request for withdrawal.
    struct UserWithdrawInfo {
        address payable recipient; //payable address of the recipient to transfer withdrawal
        uint256 batchNumber; // batch to which user request belong
        uint256 ethAmount; //eth requested according to given share and exchangeRate
        uint256 ethXAmount; //amount of ethX share locked for withdrawal
    }

    struct BatchInfo {
        bool finalized;
        uint256 startTime;
        uint256 finalizedExchangeRate;
        uint256 requiredEth;
        uint256 lockedEthX;
    }

    function initialize(address _poolManager) external initializer {
        if (_poolManager == address(0)) revert ZeroAddress();
        __AccessControl_init_unchained();
        poolManager = _poolManager;
        batchRequest[0] = BatchInfo(false, block.timestamp, 0, 0, 0);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_MANAGER, _poolManager);
    }

    /**
     * @notice put a withdrawal request and assign it to a batch
     * @param _recipient withdraw address for user to get back eth
     * @param _ethAmount eth amount to be send at the withdraw exchange rate
     * @param _ethXAmount amount of ethX shares that will be burned upon withdrawal
     */
    function withdraw(
        address msgSender,
        address payable _recipient,
        uint256 _ethAmount,
        uint256 _ethXAmount
    ) external override onlyRole(POOL_MANAGER) {
        BatchInfo memory latestBatch = batchRequest[currentBatchNumber];
        if (
            latestBatch.requiredEth + _ethAmount > requiredBatchEThThreshold ||
            latestBatch.finalized ||
            latestBatch.startTime + 24 hours > block.timestamp
        ) {
            currentBatchNumber++;
            batchRequest[currentBatchNumber] = BatchInfo(false, block.timestamp, 0, _ethAmount, _ethXAmount);
        } else {
            latestBatch.requiredEth += _ethAmount;
            latestBatch.lockedEthX += _ethXAmount;
        }
        userWithdrawRequests[msgSender].push(
            UserWithdrawInfo(payable(_recipient), currentBatchNumber, _ethAmount, _ethXAmount)
        );

        emit WithdrawRequestReceived(msgSender, _recipient, _ethXAmount, _ethAmount);
    }

    /**
     * @notice Finalize the batch from `lastFinalizedBatch` to _finalizedBatchNumber at `_finalizedExchangeRate`
     * @param _finalizedBatchNumber latest batch that is finalized
     * @param _ethToLock ether that should be locked for these requests
     * @param _finalizedExchangeRate finalized exchangeRate
     */
    function finalize(
        uint256 _finalizedBatchNumber,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) external payable override {
        if (_finalizedBatchNumber <= lastFinalizedBatch || _finalizedBatchNumber > currentBatchNumber)
            revert InvalidLastFinalizationBatch(_finalizedBatchNumber);
        if (lockedEtherAmount + _ethToLock > address(this).balance) revert InSufficientBalance();

        for (uint256 i = lastFinalizedBatch; i < _finalizedBatchNumber; ++i) {
            BatchInfo memory batchAtIndexI = batchRequest[i];
            batchAtIndexI.finalizedExchangeRate = _finalizedExchangeRate;
            batchAtIndexI.finalized = true;
        }
        lockedEtherAmount += _ethToLock;
        lastFinalizedBatch = _finalizedBatchNumber;
    }

    /**
     * @notice transfer the eth of finalized request and delete the request
     * @param _requestId request id to redeem
     */
    function redeem(uint256 _requestId) external override {
        UserWithdrawInfo[] storage userRequests = userWithdrawRequests[msg.sender];

        if (_requestId >= userRequests.length) revert InvalidRequestId(_requestId);

        UserWithdrawInfo storage userWithdrawRequest = userRequests[_requestId];
        uint256 batchNumber = userWithdrawRequest.batchNumber;
        uint256 ethXAmount = userWithdrawRequest.ethXAmount;
        uint256 ethAmount = userWithdrawRequest.ethAmount;

        BatchInfo storage userBatchRequest = batchRequest[batchNumber];
        if (!userBatchRequest.finalized) revert BatchNotFinalized(batchNumber, _requestId);
        uint256 etherToTransfer = _min((ethXAmount * userBatchRequest.finalizedExchangeRate) / 10**18, ethAmount);
        lockedEtherAmount -= etherToTransfer;
        _sendValue(userWithdrawRequest.recipient, etherToTransfer);

        userRequests[_requestId] = userRequests[userRequests.length - 1];
        userRequests.pop();

        emit RequestRedeemed(msg.sender, userWithdrawRequest.recipient, etherToTransfer);
    }

    /**
     * @notice change the recipient address of ongoing request
     * @param _requestId id of the request subject to change
     * @param _newRecipient new recipient address for withdrawal
     */
    function changeRecipient(uint256 _requestId, address _newRecipient) external override {
        UserWithdrawInfo[] storage userRequests = userWithdrawRequests[msg.sender];

        if (_requestId >= userRequests.length) revert InvalidRequestId(_requestId);

        UserWithdrawInfo storage request = userRequests[_requestId];

        if (request.recipient == _newRecipient)
            revert IdenticalRecipientAddressProvided(msg.sender, request.recipient, _requestId);

        request.recipient = payable(_newRecipient);

        emit RecipientAddressUpdated(msg.sender, _requestId, request.recipient, _newRecipient);
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
