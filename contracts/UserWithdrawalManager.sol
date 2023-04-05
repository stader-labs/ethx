// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './ETHx.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
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
    using Math for uint256;
    IStaderConfig public staderConfig;
    uint256 public override nextRequestIdToFinalize;
    uint256 public override nextRequestId;
    uint256 public override finalizationBatchLimit;
    uint256 public override ethRequestedForWithdraw;
    //upper cap on user non redeemed withdraw request count
    uint256 public override maxNonRedeemedUserRequestCount;

    bytes32 public constant override USER_WITHDRAWAL_MANAGER_ADMIN = keccak256('USER_WITHDRAWAL_MANAGER_ADMIN');

    /// @notice user withdrawal requests
    mapping(uint256 => UserWithdrawInfo) public override userWithdrawRequests;

    mapping(address => uint256[]) public override requestIdsByUserAddress;

    /// @notice structure representing a user request for withdrawal.
    struct UserWithdrawInfo {
        address payable owner; // address that can claim eth on behalf of this request
        uint256 ethXAmount; //amount of ethX share locked for withdrawal
        uint256 ethExpected; //eth requested according to given share and exchangeRate
        uint256 ethFinalized; // final eth for claiming according to finalize exchange rate
        uint256 requestTime; // timestamp of withdraw request
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        nextRequestIdToFinalize = 1;
        nextRequestId = 1;
        finalizationBatchLimit = 50;
        maxNonRedeemedUserRequestCount = 1000;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    receive() external payable {
        emit ReceivedETH(msg.value);
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

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice put a withdrawal request
     * @param _ethXAmount amount of ethX shares to withdraw
     * @param _owner owner of withdraw request to redeem
     */
    function withdraw(uint256 _ethXAmount, address _owner) external override whenNotPaused returns (uint256) {
        if (_owner == address(0)) revert ZeroAddressReceived();
        uint256 assets = IStaderStakePoolManager(staderConfig.getStakePoolManager()).previewWithdraw(_ethXAmount);
        if (assets < staderConfig.getMinWithdrawAmount() || assets > staderConfig.getMaxWithdrawAmount()) {
            revert InvalidWithdrawAmount();
        }
        if (requestIdsByUserAddress[msg.sender].length + 1 > maxNonRedeemedUserRequestCount) {
            revert MaxLimitOnWithdrawRequestCountReached();
        }
        //TODO sanjay user safeTransfer, can not use only way is to make ETHx token upgradable
        if (!ETHx(staderConfig.getETHxToken()).transferFrom(msg.sender, (address(this)), _ethXAmount)) {
            revert TokenTransferFailed();
        }
        ethRequestedForWithdraw += assets;
        userWithdrawRequests[nextRequestId] = UserWithdrawInfo(
            payable(_owner),
            _ethXAmount,
            assets,
            0,
            block.timestamp
        );
        requestIdsByUserAddress[_owner].push(nextRequestId);
        emit WithdrawRequestReceived(msg.sender, _owner, nextRequestId, _ethXAmount, assets);
        nextRequestId++;
        return nextRequestId - 1;
    }

    /**
     * @notice finalize user requests
     * @dev check for safeMode to finalizeRequest
     */
    function finalizeUserWithdrawalRequest() external override whenNotPaused {
        if (IStaderOracle(staderConfig.getStaderOracle()).safeMode()) {
            revert UnsupportedOperationInSafeMode();
        }
        address poolManager = staderConfig.getStakePoolManager();
        uint256 DECIMALS = staderConfig.getDecimals();
        uint256 exchangeRate = IStaderStakePoolManager(poolManager).getExchangeRate();
        if (exchangeRate == 0) {
            revert ProtocolNotHealthy();
        }

        uint256 maxRequestIdToFinalize = Math.min(nextRequestId, nextRequestIdToFinalize + finalizationBatchLimit) - 1;
        uint256 lockedEthXToBurn;
        uint256 ethToSendToFinalizeRequest;
        uint256 requestId;
        uint256 pooledETH = IStaderStakePoolManager(poolManager).depositedPooledETH();
        for (requestId = nextRequestIdToFinalize; requestId <= maxRequestIdToFinalize; requestId++) {
            UserWithdrawInfo memory userWithdrawInfo = userWithdrawRequests[requestId];
            uint256 requiredEth = userWithdrawInfo.ethExpected;
            uint256 lockedEthX = userWithdrawInfo.ethXAmount;
            uint256 minEThRequiredToFinalizeRequest = Math.min(requiredEth, (lockedEthX * exchangeRate) / DECIMALS);
            if (
                (ethToSendToFinalizeRequest + minEThRequiredToFinalizeRequest > pooledETH) ||
                (userWithdrawInfo.requestTime + staderConfig.getMinDelayToFinalizeWithdrawRequest() > block.timestamp)
            ) {
                requestId -= 1;
                break;
            }
            userWithdrawRequests[requestId].ethFinalized = minEThRequiredToFinalizeRequest;
            ethRequestedForWithdraw -= requiredEth;
            lockedEthXToBurn += lockedEthX;
            ethToSendToFinalizeRequest += minEThRequiredToFinalizeRequest;
        }
        if (requestId >= nextRequestIdToFinalize) {
            ETHx(staderConfig.getETHxToken()).burnFrom(address(this), lockedEthXToBurn);
            nextRequestIdToFinalize = requestId + 1;
            IStaderStakePoolManager(poolManager).transferETHToUserWithdrawManager(ethToSendToFinalizeRequest);
            emit FinalizedWithdrawRequest(requestId);
        }
    }

    /**
     * @notice transfer the eth of finalized request to recipient and delete the request
     * @param _requestId request id to redeem
     */
    function redeem(uint256 _requestId) external override {
        if (_requestId >= nextRequestIdToFinalize) {
            revert requestIdNotFinalized(_requestId);
        }
        UserWithdrawInfo memory userRequest = userWithdrawRequests[_requestId];
        if (msg.sender != userRequest.owner) {
            revert CallerNotAuthorizedToRedeem();
        }
        // below is a default entry as no userRequest will be found for a redeemed request.
        if (userRequest.ethExpected == 0) {
            revert RequestAlreadyRedeemed(_requestId);
        }
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

    // delete entry from userWithdrawRequests mapping and in requestIdsByUserAddress mapping
    function _deleteRequestId(uint256 _requestId, address _owner) internal {
        delete (userWithdrawRequests[_requestId]);
        uint256 userRequestCount = requestIdsByUserAddress[_owner].length;
        uint256[] storage requestIds = requestIdsByUserAddress[_owner];
        for (uint256 i = 0; i < userRequestCount; i++) {
            if (_requestId == requestIds[i]) {
                requestIds[i] = requestIds[userRequestCount - 1];
                requestIds.pop();
                return;
            }
        }
        revert CannotFindRequestId();
    }

    function _sendValue(address payable _recipient, uint256 _amount) internal {
        if (address(this).balance < _amount) {
            revert InSufficientBalance();
        }

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = _recipient.call{value: _amount}('');
        if (!success) {
            revert TransferFailed();
        }
    }
}
