// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';

import './ETHx.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract UserWithdrawalManager is
    IUserWithdrawalManager,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bool public override slashingMode; //TODO sanjay read this from stader oracle contract
    address public override ethX; //TODO sanjay not setting the value for now, will read from index contract
    address public override poolManager; //TODO sanjay not setting the value for now, will read from index contract
    uint256 public constant override DECIMALS = 10**18;
    uint256 public override nextRequestIdToFinalize;
    uint256 public override nextRequestId;
    uint256 public override minWithdrawAmount;
    uint256 public override maxWithdrawAmount;
    uint256 public override finalizationBatchLimit;
    uint256 public override ethRequestedForWithdraw;
    //upper cap on user non redeemed withdraw request count
    uint256 public override maxNonRedeemedUserRequestCount;

    bytes32 public constant override USER_WITHDRAWAL_MANAGER_ADMIN = keccak256('USER_WITHDRAWAL_MANAGER_ADMIN');

    /// @notice user withdrawal requests
    mapping(uint256 => UserWithdrawInfo) public override userWithdrawRequests;

    //TODO sanjay cap the size of array
    //TODO sanjay delete entry once redeemed
    mapping(address => uint256[]) public override requestIdsByUserAddress;

    /// @notice structure representing a user request for withdrawal.
    struct UserWithdrawInfo {
        address payable owner; // address that can claim eth on behalf of this request
        uint256 ethXAmount; //amount of ethX share locked for withdrawal
        uint256 ethExpected; //eth requested according to given share and exchangeRate
        uint256 ethFinalized; // final eth for claiming according to finalize exchange rate
    }

    function initialize(address _admin) external initializer {
        Address.checkNonZeroAddress(_admin);
        __AccessControl_init_unchained();
        __Pausable_init();
        __ReentrancyGuard_init();
        nextRequestIdToFinalize = 1;
        nextRequestId = 1;
        minWithdrawAmount = 100;
        maxWithdrawAmount = 10000 ether;
        finalizationBatchLimit = 50;
        maxNonRedeemedUserRequestCount = 1000;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function receiveETHToFinalizeRequest() external payable override {
        //TODO call this poolManager from index file
        if (msg.sender != poolManager) revert OnlyStaderStakePoolManagerCanCall();
        emit ReceivedETHToFinalizeRequests(msg.value);
    }

    /**
     * @dev update the minimum withdraw amount
     * @param _minWithdrawAmount minimum withdraw value
     */
    function updateMinWithdrawAmount(uint256 _minWithdrawAmount)
        external
        override
        onlyRole(USER_WITHDRAWAL_MANAGER_ADMIN)
    {
        if (_minWithdrawAmount == 0 || _minWithdrawAmount > maxWithdrawAmount) revert InvalidMinWithdrawValue();
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
        onlyRole(USER_WITHDRAWAL_MANAGER_ADMIN)
    {
        if (_maxWithdrawAmount < minWithdrawAmount) revert InvalidMaxWithdrawValue();
        maxWithdrawAmount = _maxWithdrawAmount;
        emit UpdatedMaxWithdrawAmount(maxWithdrawAmount);
    }

    /**
     * @notice update the finalizationBatchLimit value
     * @dev only admin of this contract can call
     * @param _finalizationBatchLimit value of finalizationBatchLimit
     */
    function updateFinalizationBatchLimit(uint256 _finalizationBatchLimit)
        external
        override
        onlyRole(USER_WITHDRAWAL_MANAGER_ADMIN)
    {
        finalizationBatchLimit = _finalizationBatchLimit;
        emit UpdatedFinalizationBatchLimit(_finalizationBatchLimit);
    }

    /**
     * @notice put a withdrawal request
     * @param _ethXAmount amount of ethX shares to withdraw
     * @param _owner owner of withdraw request to redeem
     */
    function withdraw(uint256 _ethXAmount, address _owner) external override whenNotPaused returns (uint256) {
        uint256 assets = IStaderStakePoolManager(poolManager).previewWithdraw(_ethXAmount);
        if (assets < minWithdrawAmount || assets > maxWithdrawAmount) revert InvalidWithdrawAmount();
        if (requestIdsByUserAddress[msg.sender].length + 1 > maxNonRedeemedUserRequestCount)
            revert MaxLimitOnWithdrawRequestCountReached();
        //TODO sanjay user safeTransfer
        if (_owner == address(0)) _owner = msg.sender;
        if (!ETHx(ethX).transferFrom(msg.sender, (address(this)), _ethXAmount)) revert TokenTransferFailed();
        ethRequestedForWithdraw += assets;
        userWithdrawRequests[nextRequestId] = UserWithdrawInfo(payable(_owner), _ethXAmount, assets, 0);
        requestIdsByUserAddress[_owner].push(nextRequestId);
        emit WithdrawRequestReceived(msg.sender, _owner, nextRequestId, _ethXAmount, assets);
        nextRequestId++;
        return nextRequestId - 1;
    }

    /**
     * @notice finalize user requests
     * @dev when slashing mode, only process and don't finalize
     */
    function finalizeUserWithdrawalRequest() external override whenNotPaused {
        //TODO sanjay read from index file
        if (slashingMode) revert ProtocolInSlashingMode();
        uint256 exchangeRate = IStaderStakePoolManager(poolManager).getExchangeRate();
        if (exchangeRate == 0) revert ProtocolNotHealthy();

        uint256 maxRequestIdToFinalize = _min(nextRequestId, nextRequestIdToFinalize + finalizationBatchLimit) - 1;
        uint256 lockedEthXToBurn;
        uint256 ethToSendToFinalizeRequest;
        uint256 requestId;
        uint256 pooledETH = IStaderStakePoolManager(poolManager).depositedPooledETH();
        for (requestId = nextRequestIdToFinalize; requestId <= maxRequestIdToFinalize; requestId++) {
            uint256 requiredEth = userWithdrawRequests[requestId].ethExpected;
            uint256 lockedEthX = userWithdrawRequests[requestId].ethXAmount;
            uint256 minEThRequiredToFinalizeRequest = _min(requiredEth, (lockedEthX * exchangeRate) / DECIMALS);
            if (ethToSendToFinalizeRequest + minEThRequiredToFinalizeRequest > pooledETH) {
                requestId -= 1;
                break;
            }
            userWithdrawRequests[requestId].ethFinalized = minEThRequiredToFinalizeRequest;
            ethRequestedForWithdraw -= requiredEth;
            lockedEthXToBurn += lockedEthX;
            ethToSendToFinalizeRequest += minEThRequiredToFinalizeRequest;
        }
        if (requestId >= nextRequestIdToFinalize) {
            ETHx(ethX).burnFrom(address(this), lockedEthXToBurn);
            nextRequestIdToFinalize = requestId + 1;
            IStaderStakePoolManager(poolManager).transferETHToUserWithdrawManager(ethToSendToFinalizeRequest);
        }
    }

    /**
     * @notice transfer the eth of finalized request to recipient and delete the request
     * @param _requestId request id to redeem
     */
    //TODO only allow owner/recipient to redeem
    function redeem(uint256 _requestId) external override {
        if (_requestId >= nextRequestIdToFinalize) revert requestIdNotFinalized(_requestId);
        UserWithdrawInfo memory userRequest = userWithdrawRequests[_requestId];
        if (msg.sender != userRequest.owner) revert CallerNotAuthorizedToRedeem();
        // below is a default entry as no userRequest will be found for a redeemed request.
        if (userRequest.ethExpected == 0) revert RequestAlreadyRedeemed(_requestId);
        uint256 etherToTransfer = userRequest.ethFinalized;
        _deleteRequestId(_requestId, userRequest.owner);
        _sendValue(userRequest.owner, etherToTransfer);
        emit RequestRedeemed(msg.sender, userRequest.owner, etherToTransfer);
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(USER_WITHDRAWAL_MANAGER_ADMIN) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(USER_WITHDRAWAL_MANAGER_ADMIN) {
        _unpause();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // delete entry from userWithdrawRequests mapping and in requestIdsByUserAddress mapping
    function _deleteRequestId(uint256 _requestId, address _owner) internal {
        delete (userWithdrawRequests[_requestId]);
        uint256 userRequestCount = requestIdsByUserAddress[_owner].length;
        for (uint256 i = 0; i < userRequestCount; i++) {
            //TODO check if we can define `requestIdsByUserAddress[_owner]` as a variable
            if (_requestId == requestIdsByUserAddress[_owner][i]) {
                requestIdsByUserAddress[_owner][i] = requestIdsByUserAddress[_owner][userRequestCount - 1];
                requestIdsByUserAddress[_owner].pop();
                return;
            }
        }
        revert CannotFindRequestId();
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InSufficientBalance();

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = recipient.call{value: amount}('');
        if (!success) revert TransferFailed();
    }
}
