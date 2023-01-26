pragma solidity ^0.8.16;

import './interfaces/IStaderWithdrawalManager.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderWithdrawalManager is Initializable, AccessControlUpgradeable {
    bytes32 public constant  POOL_MANAGER = keccak256('POOL_MANAGER');
    address public poolManager;

    uint256 public  lockedEtherAmount ;

    uint256 public  processedRequestCounter;

    uint256 public constant MIN_WITHDRAWAL = 0.1 ether;

    /// @notice queue for withdrawal requests
    WithdrawInfo[] public withdrawRequest;

    /// @notice length of the finalized part of the queue
    uint256 public  finalizedRequestsCounter ;

    /// @notice structure representing a request for withdrawal.
    struct WithdrawInfo {
        /// @notice flag if the request was already claimed
        bool claimed;
        /// @notice payable address of the recipient withdrawal will be transferred to
        address payable recipient;
        /// @notice sum of the all requested ether including this request
        uint256 cumulativeEther;
        /// @notice sum of the all shares locked for withdrawal including this request
        uint256 cumulativeShares;
        /// @notice block.number when the request created
        uint256 requestBlockNumber;
    }

    /// @notice finalization price history registry
    Price[] public  finalizationPrices;

    /**
     * @notice structure representing share price for some range in request queue
     * @dev price is stored as a pair of value that should be divided later
     */
    struct Price {
        uint256 totalUserTVL;
        uint256 totalShares;
        /// @notice last index in queue this price is actual for
        uint256 index;
    }

    function initialize(address _poolManager) external initializer {
        require(_poolManager != address(0), 'ZERO_OWNER');
        __AccessControl_init_unchained();
        poolManager = _poolManager;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_MANAGER, _poolManager);
    }

    /**
     * @notice put a withdrawal request in a queue and associate it with `_recipient` address
     * @dev Assumes that `_ethAmount` of stETH is locked before invoking this function
     * @param _recipient payable address this request will be associated with
     * @param _etherAmount maximum amount of ether (equal to amount of locked stETH) that will be claimed upon withdrawal
     * @param _sharesAmount amount of stETH shares that will be burned upon withdrawal
     * @return requestId unique id to claim funds once it is available
     */
    function withdraw(
        address payable _recipient,
        uint256 _etherAmount,
        uint256 _sharesAmount
    ) external onlyRole(POOL_MANAGER) returns (uint256 requestId) {
        require(_etherAmount > MIN_WITHDRAWAL, 'WITHDRAWAL_IS_TOO_SMALL');
        requestId = withdrawRequest.length;

        uint256 cumulativeEther = _etherAmount;
        uint256 cumulativeShares = _sharesAmount;

        if (requestId > 0) {
            cumulativeEther += withdrawRequest[requestId - 1].cumulativeEther;
            cumulativeShares += withdrawRequest[requestId - 1].cumulativeShares;
        }

        withdrawRequest.push(WithdrawInfo(false, _recipient, cumulativeEther, cumulativeShares, block.number));
    }

    /**
     * @notice Finalize the batch of requests started at `finalizedRequestsCounter` and ended at `_lastIdToFinalize` using the given price
     * @param _lastIdToFinalize request index in the queue that will be last finalized request in a batch
     * @param _etherToLock ether that should be locked for these requests
     * @param _totalUserTVL ether price component that will be used for this request batch finalization
     * @param _totalShares shares price component that will be used for this request batch finalization
     */
    function finalize(
        uint256 _lastIdToFinalize,
        uint256 _etherToLock,
        uint256 _totalUserTVL,
        uint256 _totalShares
    ) external payable  onlyRole(POOL_MANAGER) {
        require(
            _lastIdToFinalize >= finalizedRequestsCounter && _lastIdToFinalize < withdrawRequest.length,
            'INVALID_FINALIZATION_ID'
        );
        require(lockedEtherAmount + _etherToLock <= address(this).balance, 'NOT_ENOUGH_ETHER');

        _updatePriceHistory(_totalUserTVL, _totalShares, _lastIdToFinalize);

        lockedEtherAmount = _etherToLock;
        finalizedRequestsCounter = _lastIdToFinalize + 1;
    }

    /**
     * @notice Mark `_requestId` request as claimed and transfer reserved ether to recipient
     * @param _requestId request id to claim
     */
    function redeem(uint256 _requestId) external  returns (address recipient) {
        // request must be finalized
        require(finalizedRequestsCounter > _requestId, 'REQUEST_NOT_FINALIZED');

        WithdrawInfo storage request = withdrawRequest[_requestId];
        require(!request.claimed, 'REQUEST_ALREADY_CLAIMED');

        request.claimed = true;

        Price memory price;
        price = finalizationPrices[findPriceHint(_requestId)];

        (uint256 etherToTransfer, ) = _calculateDiscountedBatch(
            _requestId,
            _requestId,
            price.totalUserTVL,
            price.totalShares
        );
        lockedEtherAmount -= etherToTransfer;

        _sendValue(request.recipient, etherToTransfer);

        return request.recipient;
    }

    /**
     * @notice calculates the params to fulfill the next batch of requests in queue
     * @param _lastIdToFinalize last id in the queue to finalize upon
     * @param _totalUserTVL share price component to finalize requests
     * @param _totalShares share price component to finalize requests
     *
     * @return etherToLock amount of eth required to finalize the batch
     * @return sharesToBurn amount of shares that should be burned on finalization
     */
    function calculateFinalizationParams(
        uint256 _lastIdToFinalize,
        uint256 _totalUserTVL,
        uint256 _totalShares
    ) external view  returns (uint256 etherToLock, uint256 sharesToBurn) {
        return _calculateDiscountedBatch(finalizedRequestsCounter, _lastIdToFinalize, _totalUserTVL, _totalShares);
    }

    function findPriceHint(uint256 _requestId) public view returns (uint256 hint) {
        require(_requestId < finalizedRequestsCounter, 'PRICE_NOT_FOUND');

        for (uint256 i = finalizationPrices.length; i > 0; i--) {
            if (_isPriceHintValid(_requestId, i - 1)) {
                return i - 1;
            }
        }
        require(false);
    }

    // function restake(uint256 _amount) external  onlyRole(POOL_MANAGER) {
    //     require(lockedEtherAmount + _amount <= address(this).balance, 'NOT_ENOUGH_ETHER');

    //     IRestakingSink(poolManager).receiveRestake{value: _amount}();
    // }

    function getLatestRequestId() public view returns(uint256 requestId){
        return withdrawRequest.length;
    }

    function _calculateDiscountedBatch(
        uint256 firstId,
        uint256 lastId,
        uint256 _totalUserTVL,
        uint256 _totalShares
    ) internal view returns (uint256 eth, uint256 shares) {
        eth = withdrawRequest[lastId].cumulativeEther;
        shares = withdrawRequest[lastId].cumulativeShares;

        if (firstId > 0) {
            eth -= withdrawRequest[firstId - 1].cumulativeEther;
            shares -= withdrawRequest[firstId - 1].cumulativeShares;
        }

        eth = _min(eth, (shares * _totalUserTVL) / _totalShares);
    }

    function _isPriceHintValid(uint256 _requestId, uint256 hint) internal view returns (bool isInRange) {
        uint256 hintLastId = finalizationPrices[hint].index;

        isInRange = _requestId <= hintLastId;
        if (hint > 0) {
            uint256 previousId = finalizationPrices[hint - 1].index;

            isInRange = isInRange && previousId < _requestId;
        }
    } 

    function _updatePriceHistory(
        uint256 _totalUserTVL,
        uint256 _totalShares,
        uint256 index
    ) internal {
        if (finalizationPrices.length == 0) {
            finalizationPrices.push(Price(_totalUserTVL, _totalShares, index));
        } else {
            Price storage lastPrice = finalizationPrices[finalizationPrices.length - 1];

            if (_totalUserTVL / _totalShares == lastPrice.totalUserTVL / lastPrice.totalShares) {
                lastPrice.index = index;
            } else {
                finalizationPrices.push(Price(_totalUserTVL, _totalShares, index));
            }
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        // solhint-disable-next-line
        (bool success, ) = recipient.call{value: amount}('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }
}
