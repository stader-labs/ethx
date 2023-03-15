// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';

import './ETHX.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract UserWithdrawalManager is IUserWithdrawalManager, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    bytes32 public constant USER_WITHDRAW_MANAGER_ADMIN = keccak256('USER_WITHDRAW_MANAGER_ADMIN');

    bool public slashingMode; //TODO read this from stader oracle contract
    address public ethX; //not setting the value for now, will read from index contract
    address public poolManager; //not setting the value for now, will read from index contract
    uint256 public constant override DECIMALS = 10**18;
    uint256 public override lockedEtherAmount;
    uint256 public override nextRequestIdToFinalize;
    uint256 public override latestRequestId;
    uint256 public minWithdrawAmount;
    uint256 public maxWithdrawAmount;
    uint256 public paginationLimit;
    uint256 public override ethRequestedForWithdraw;

    /// @notice user withdrawal requests
    mapping(uint256 => UserWithdrawInfo) public override userWithdrawRequests;

    mapping(address => uint256[]) public override requestIdsByUserAddress;

    /// @notice structure representing a user request for withdrawal.
    struct UserWithdrawInfo {
        bool redeemStatus; //withdraw request redeemed if variable is true
        address owner; // ethX owner
        address payable recipient; //payable address of the recipient to transfer withdrawal
        uint256 ethAmount; //eth requested according to given share and exchangeRate
        uint256 ethXAmount; //amount of ethX share locked for withdrawal
        uint256 finalizedExchangeRate; // exchange rate at which withdraw request is finalized
    }

    function initialize(address _admin) external initializer {
        Address.checkNonZeroAddress(_admin);
        __AccessControl_init_unchained();
        __Pausable_init();
        nextRequestIdToFinalize = 1;
        latestRequestId = 1;
        minWithdrawAmount = 100;
        maxWithdrawAmount = 10 ether;
        paginationLimit = 50;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @dev update the minimum withdraw amount
     * @param _minWithdrawAmount minimum withdraw value
     */
    function updateMinWithdrawAmount(uint256 _minWithdrawAmount)
        external
        override
        onlyRole(USER_WITHDRAW_MANAGER_ADMIN)
    {
        if (_minWithdrawAmount == 0) revert InvalidMinWithdrawValue();
        minWithdrawAmount = _minWithdrawAmount;
        emit UpdatedMinWithdrawAmount(minWithdrawAmount);
    }

    /**
     * @dev update the maximum withdraw amount
     * @param _maxWithdrawAmount maximum withdraw value
     */
    function updateMaxWithdrawAmount(uint256 _maxWithdrawAmount)
        external
        override
        onlyRole(USER_WITHDRAW_MANAGER_ADMIN)
    {
        if (_maxWithdrawAmount <= minWithdrawAmount) revert InvalidMaxWithdrawValue();
        maxWithdrawAmount = _maxWithdrawAmount;
        emit UpdatedMaxWithdrawAmount(maxWithdrawAmount);
    }

    /**
     * @notice update the paginationLimit value
     * @dev only admin of this contract can call
     * @param _paginationLimit value of paginationLimit
     */
    function updatePaginationLimit(uint256 _paginationLimit) external override onlyRole(USER_WITHDRAW_MANAGER_ADMIN) {
        paginationLimit = _paginationLimit;
    }

    /**
     * @notice put a withdrawal request
     * @param _ethXAmount amount of ethX shares to withdraw
     * @param receiver withdraw address for user to get back eth
     */
    function withdraw(uint256 _ethXAmount, address receiver) external override whenNotPaused returns (uint256) {
        uint256 assets = IStaderStakePoolManager(poolManager).previewWithdraw(_ethXAmount);
        if (assets < minWithdrawAmount || assets > maxWithdrawAmount) revert InvalidWithdrawAmount();
        address msgSender = msg.sender;
        ETHX(ethX).transferFrom(msgSender, (address(this)), _ethXAmount);
        userWithdrawRequests[latestRequestId] = UserWithdrawInfo(
            false,
            msgSender,
            payable(receiver),
            assets,
            _ethXAmount,
            0
        );
        requestIdsByUserAddress[msgSender].push(latestRequestId);
        latestRequestId++;
        emit WithdrawRequestReceived(msgSender, receiver, latestRequestId - 1, _ethXAmount, assets);
        return latestRequestId - 1;
    }

    /**
     * @notice finalize user requests
     * @dev when slashing mode, only process and don't finalize
     */
    function finalizeUserWithdrawalRequest() external override whenNotPaused {
        //TODO change input name
        if (!slashingMode) {
            uint256 exchangeRate = IStaderStakePoolManager(poolManager).getExchangeRate();
            if (exchangeRate == 0) revert ProtocolNotHealthy();

            uint256 maxRequestIdToFinalize = _min(latestRequestId, nextRequestIdToFinalize + paginationLimit);
            uint256 lockedEthXToBurn;
            uint256 ethToSendToFinalizeRequest;
            uint256 requestId;
            uint256 pooledETH = IStaderStakePoolManager(poolManager).depositedPooledETH();
            for (requestId = nextRequestIdToFinalize; requestId < maxRequestIdToFinalize; requestId++) {
                uint256 requiredEth = userWithdrawRequests[requestId].ethAmount;
                uint256 lockedEthX = userWithdrawRequests[requestId].ethXAmount;
                uint256 minEThRequiredToFinalizeRequest = _min(requiredEth, (lockedEthX * exchangeRate) / DECIMALS);
                if (minEThRequiredToFinalizeRequest > pooledETH) {
                    break;
                } else {
                    lockedEthXToBurn += lockedEthX;
                    ethToSendToFinalizeRequest += minEThRequiredToFinalizeRequest;
                    pooledETH -= minEThRequiredToFinalizeRequest;
                }
            }
            if (requestId >= nextRequestIdToFinalize) {
                ETHX(ethX).burnFrom(address(this), lockedEthXToBurn);
                IStaderStakePoolManager(poolManager).transferETHToUserWithdrawManager(ethToSendToFinalizeRequest);
                _finalize(requestId, ethToSendToFinalizeRequest, exchangeRate);
            }
        }
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

        uint256 etherToTransfer = _min((ethXAmount * userRequest.finalizedExchangeRate) / DECIMALS, ethAmount);
        lockedEtherAmount -= etherToTransfer;
        _sendValue(userRequest.recipient, etherToTransfer);

        emit RequestRedeemed(msg.sender, userRequest.recipient, etherToTransfer);
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(USER_WITHDRAW_MANAGER_ADMIN) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(USER_WITHDRAW_MANAGER_ADMIN) {
        _unpause();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Finalize the request from `nextRequestIdToFinalize` to _finalizeRequestId at `_finalizedExchangeRate`
     * @param _finalizeRequestId request ID to finalize up to from nextRequestIdToFinalize
     * @param _ethToLock ether that should be locked for these requests
     * @param _finalizedExchangeRate finalized exchangeRate
     */
    function _finalize(
        uint256 _finalizeRequestId,
        uint256 _ethToLock,
        uint256 _finalizedExchangeRate
    ) internal {
        if (_finalizeRequestId < nextRequestIdToFinalize || _finalizeRequestId >= latestRequestId)
            revert InvalidFinalizationRequestId(_finalizeRequestId);
        if (lockedEtherAmount + _ethToLock > address(this).balance) revert InSufficientBalance();

        for (uint256 i = nextRequestIdToFinalize; i <= _finalizeRequestId; i++) {
            userWithdrawRequests[i].finalizedExchangeRate = _finalizedExchangeRate;
        }
        lockedEtherAmount += _ethToLock;
        nextRequestIdToFinalize = _finalizeRequestId + 1;
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InSufficientBalance();

        // solhint-disable-next-line
        (bool success, ) = recipient.call{value: amount}('');
        if (!success) revert TransferFailed();
    }
}
