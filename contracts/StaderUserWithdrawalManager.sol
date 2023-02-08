pragma solidity ^0.8.16;

import './interfaces/IStaderUserWithdrawalManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderUserWithdrawalManager is IStaderUserWithdrawalManager, Initializable, AccessControlUpgradeable {
    
    bytes32 public constant override POOL_MANAGER = keccak256('POOL_MANAGER');

    address public override staderOwner;

    uint256 public constant override DECIMAL = 10**18;

    uint256 public override lockedEtherAmount;

    uint256 public override nextBatchIdToFinalize;

    uint256 public override latestBatchId;

    uint256 public override lastIncrementBatchTime;

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

    function initialize(address _staderOwner) external initializer {
        if (_staderOwner == address(0)) revert ZeroAddress();
        __AccessControl_init_unchained();
        staderOwner = _staderOwner;
        batchRequest[0] = BatchInfo(true, block.timestamp, 0, 0, 0);
        batchRequest[1] = BatchInfo(false, block.timestamp, 0, 0, 0);
        nextBatchIdToFinalize = 1;
        latestBatchId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

        BatchInfo memory latestBatch = batchRequest[latestBatchId];
        latestBatch.requiredEth += _ethAmount;
        latestBatch.lockedEthX += _ethXAmount;
        userWithdrawRequests[msgSender].push(
            UserWithdrawInfo(payable(_recipient), latestBatchId, _ethAmount, _ethXAmount)
        );

        emit WithdrawRequestReceived(msgSender, _recipient, _ethXAmount, _ethAmount);
    }

    /**
     * @notice Finalize the batch from `lastFinalizedBatch` to _finalizedBatchNumber at `_finalizedExchangeRate`
     * @param _finalizeBatchId batch ID to finalize up to from latestFinalizedBatchId
     * @param _ethToLock ether that should be locked for these requests
     * @param _finalizedExchangeRate finalized exchangeRate
     */
    function finalize(
        uint256 _finalizeBatchId,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) external payable override onlyRole(POOL_MANAGER){
        if (_finalizeBatchId < nextBatchIdToFinalize || _finalizeBatchId >= latestBatchId)
            revert InvalidLastFinalizationBatch(_finalizeBatchId);
        if (lockedEtherAmount + _ethToLock > address(this).balance) revert InSufficientBalance();

        for (uint256 i = nextBatchIdToFinalize; i <= _finalizeBatchId; i++) {
            BatchInfo memory batchAtIndexI = batchRequest[i];
            batchAtIndexI.finalizedExchangeRate = _finalizedExchangeRate;
            batchAtIndexI.finalized = true;
        }
        lockedEtherAmount += _ethToLock;
        nextBatchIdToFinalize = _finalizeBatchId+1;
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
        uint256 etherToTransfer = _min((ethXAmount * userBatchRequest.finalizedExchangeRate) / DECIMAL, ethAmount);
        lockedEtherAmount -= etherToTransfer;
        _sendValue(userWithdrawRequest.recipient, etherToTransfer);

        userRequests[_requestId] = userRequests[userRequests.length - 1];
        userRequests.pop();

        emit RequestRedeemed(msg.sender, userWithdrawRequest.recipient, etherToTransfer);
    }

/**
 * @notice creates a new batch
 * @dev anyone can call after 24 hours from last incrementBatch, 
 *  staderOwner can bypass the time check
 */
    function incrementBatch() external {
        address sender  = msg.sender;
        if(batchRequest[latestBatchId].requiredEth==0){
            return;
        }
        if(sender != staderOwner && lastIncrementBatchTime+24 hours > block.timestamp){
            return;
        }
        latestBatchId = latestBatchId+1;
        lastIncrementBatchTime = block.timestamp;
        batchRequest[latestBatchId] = BatchInfo(false, block.timestamp, 0, 0, 0);
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
