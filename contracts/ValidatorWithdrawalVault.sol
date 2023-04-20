// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IPenalty.sol';
import './interfaces/IPoolUtils.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IValidatorWithdrawalVault.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract ValidatorWithdrawalVault is
    IValidatorWithdrawalVault,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;

    bool public override vaultSettleStatus;
    uint8 public override poolId; // No Setter as this is supposed to be set once
    IStaderConfig public override staderConfig;
    uint256 public override validatorId; // No Setter as this is supposed to be set once

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint8 _poolId,
        address _staderConfig,
        uint256 _validatorId
    ) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init_unchained();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        poolId = _poolId;
        validatorId = _validatorId;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    // Allows the contract to receive ETH
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function distributeRewards() external override nonReentrant {
        uint256 totalRewards = address(this).balance;
        if (vaultSettleStatus) {
            sendValue(payable(staderConfig.getStaderTreasury()), address(this).balance);
            return;
        }
        if (!staderConfig.onlyOperatorRole(msg.sender) && totalRewards > staderConfig.getRewardsThreshold()) {
            emit DistributeRewardFailed(totalRewards, staderConfig.getRewardsThreshold());
            revert InvalidRewardAmount();
        }
        if (totalRewards == 0) {
            revert NotEnoughRewardToDistribute();
        }
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = IPoolUtils(staderConfig.getPoolUtils())
            .calculateRewardShare(poolId, totalRewards);

        // Distribute rewards
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        sendValue(getNodeRecipient(), operatorShare);
        sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        emit DistributedRewards(userShare, operatorShare, protocolShare);
    }

    function settleFunds() external override nonReentrant returns (uint256 _sdSlashed) {
        if (!isWithdrawnValidator() || vaultSettleStatus) {
            revert ValidatorNotWithdrawnOrSettled();
        }
        (uint256 userSharePrelim, uint256 operatorShare, uint256 protocolShare) = calculateValidatorWithdrawalShare();

        uint256 penaltyAmount = getPenaltyAmount();

        if (operatorShare < penaltyAmount) {
            _sdSlashed = ISDCollateral(staderConfig.getSDCollateral()).slashValidatorSD(validatorId, poolId);
            penaltyAmount = operatorShare;
        }

        uint256 userShare = userSharePrelim + penaltyAmount;
        operatorShare = operatorShare - penaltyAmount;

        // Final settlement
        vaultSettleStatus = true;
        IPenalty(staderConfig.getPenaltyContract()).markValidatorSettled(poolId, validatorId);
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        sendValue(getNodeRecipient(), operatorShare);
        sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        emit SettledFunds(userShare, operatorShare, protocolShare);
    }

    function calculateValidatorWithdrawalShare()
        public
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH(); // 0, incase of permissioned NOs
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 contractBalance = address(this).balance;

        uint256 totalRewards;

        if (contractBalance <= usersETH) {
            _userShare = contractBalance;
            return (_userShare, _operatorShare, _protocolShare);
        } else if (contractBalance <= TOTAL_STAKED_ETH) {
            _userShare = usersETH;
            _operatorShare = contractBalance - _userShare;
            return (_userShare, _operatorShare, _protocolShare);
        } else {
            totalRewards = contractBalance - TOTAL_STAKED_ETH;
            _operatorShare = collateralETH;
            _userShare = usersETH;
        }
        if (totalRewards > 0) {
            (uint256 userReward, uint256 operatorReward, uint256 protocolReward) = IPoolUtils(
                staderConfig.getPoolUtils()
            ).calculateRewardShare(poolId, totalRewards);
            _userShare += userReward;
            _operatorShare += operatorReward;
            _protocolShare += protocolReward;
        }
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function sendValue(address payable _recipient, uint256 _amount) internal {
        if (address(this).balance < _amount) {
            revert InsufficientBalance();
        }

        //slither-disable-next-line arbitrary-send-eth
        if (_amount > 0) {
            (bool success, ) = _recipient.call{value: _amount}('');
            if (!success) {
                revert ETHTransferFailed(_recipient, _amount);
            }
        }
    }

    // HELPER METHODS

    function getCollateralETH() internal view returns (uint256) {
        return IPoolUtils(staderConfig.getPoolUtils()).getCollateralETH(poolId);
    }

    function getNodeRecipient() internal view returns (address payable) {
        return UtilLib.getNodeRecipientAddressByValidatorId(poolId, validatorId, staderConfig);
    }

    function getPenaltyAmount() internal returns (uint256) {
        address nodeRegistry = IPoolUtils(staderConfig.getPoolUtils()).getNodeRegistry(poolId);
        (, bytes memory pubkey, , , , , , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        bytes[] memory pubkeyArray = new bytes[](1);
        pubkeyArray[0] = pubkey;
        IPenalty(staderConfig.getPenaltyContract()).updateTotalPenaltyAmount(pubkeyArray);
        return IPenalty(staderConfig.getPenaltyContract()).totalPenaltyAmount(pubkey);
    }

    function isWithdrawnValidator() internal view returns (bool) {
        address nodeRegistry = IPoolUtils(staderConfig.getPoolUtils()).getNodeRegistry(poolId);
        (ValidatorStatus status, , , , , , , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        return status == ValidatorStatus.WITHDRAWN;
    }
}
