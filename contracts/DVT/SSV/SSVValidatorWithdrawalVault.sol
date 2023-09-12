// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../library/UtilLib.sol';
import './SSVVaultProxy.sol';
import '../../interfaces/IPenalty.sol';
import '../../interfaces/IPoolUtils.sol';
import '../../interfaces/IStaderStakePoolManager.sol';
import '../../interfaces/DVT/SSV/ISSVNodeRegistry.sol';
import '../../interfaces/IOperatorRewardsCollector.sol';
import '../../interfaces/SDCollateral/ISDCollateral.sol';
import '../../interfaces/DVT/SSV/ISSVValidatorWithdrawalVault.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';

contract SSVValidatorWithdrawalVault is ISSVValidatorWithdrawalVault {
    bool internal vaultSettleStatus;
    using Math for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    // Allows the contract to receive ETH
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function distributeRewards() external override {
        uint8 poolId = SSVVaultProxy(payable(address(this))).poolId();
        uint256 validatorId = SSVVaultProxy(payable(address(this))).validatorId();
        IStaderConfig staderConfig = SSVVaultProxy(payable(address(this))).staderConfig();
        ISSVNodeRegistry nodeRegistry = ISSVNodeRegistry(
            IPoolUtils(staderConfig.getPoolUtils()).getNodeRegistry(poolId)
        );

        uint256 totalRewards = address(this).balance;
        if (!staderConfig.onlyManagerRole(msg.sender) && totalRewards > staderConfig.getRewardsThreshold()) {
            emit DistributeRewardFailed(totalRewards, staderConfig.getRewardsThreshold());
            revert InvalidRewardAmount();
        }
        if (totalRewards == 0) {
            revert NotEnoughRewardToDistribute();
        }
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = IPoolUtils(staderConfig.getPoolUtils())
            .calculateRewardShare(poolId, totalRewards);

        //TODO add documentation for this formula
        // Distribute rewards
        uint64[] memory operatorIds = nodeRegistry.getOperatorsIdsForValidatorId(validatorId);
        uint256 totalOperators = operatorIds.length;
        for (uint8 i; i < totalOperators; ) {
            (bool operatorType, , , address operatorAddress, , , ) = nodeRegistry.operatorStructById(operatorIds[i]);
            uint256 operatorKeyLevelShare;
            if (operatorType) {
                operatorKeyLevelShare = getPermissionedOperatorShare(
                    operatorShare,
                    totalRewards,
                    staderConfig.getStakedEthPerNode(),
                    nodeRegistry
                );
            } else {
                operatorKeyLevelShare = getPermissionlessOperatorShare(
                    operatorShare,
                    totalRewards,
                    staderConfig.getStakedEthPerNode(),
                    nodeRegistry
                );
            }
            IOperatorRewardsCollector(staderConfig.getOperatorRewardsCollector()).depositFor{
                value: operatorKeyLevelShare
            }(operatorAddress);
            unchecked {
                i++;
            }
        }
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        UtilLib.sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        emit DistributedRewards(userShare, operatorShare, protocolShare);
    }

    function settleFunds() external override {
        uint8 poolId = SSVVaultProxy(payable(address(this))).poolId();
        uint256 validatorId = SSVVaultProxy(payable(address(this))).validatorId();
        IStaderConfig staderConfig = SSVVaultProxy(payable(address(this))).staderConfig();
        if (msg.sender != IPoolUtils(staderConfig.getPoolUtils()).getNodeRegistry(poolId)) {
            revert CallerNotNodeRegistryContract();
        }
        uint64[] memory operatorIds = ISSVNodeRegistry(msg.sender).getOperatorsIdsForValidatorId(validatorId);
        uint256 totalOperators = operatorIds.length;

        (uint256 userSharePrelim, uint256 operatorShare, uint256 protocolShare) = calculateValidatorWithdrawalShare(
            poolId,
            staderConfig
        );

        uint256 penaltyAmount = getUpdatedPenaltyAmount(validatorId, staderConfig);
        uint256 permissionedOperatorShare;
        uint256 permissionlessOperatorShare;
        uint256 collateralETH = ISSVNodeRegistry(msg.sender).getCollateralETH();
        if (operatorShare <= collateralETH) {
            permissionlessOperatorShare = operatorShare / (ISSVNodeRegistry(msg.sender).CLUSTER_SIZE() / 2);
        } else {
            uint256 rewards = address(this).balance - staderConfig.getStakedEthPerNode();
            permissionedOperatorShare = getPermissionedOperatorShare(
                operatorShare - collateralETH,
                rewards,
                staderConfig.getStakedEthPerNode(),
                ISSVNodeRegistry(msg.sender)
            );

            permissionlessOperatorShare =
                collateralETH /
                (ISSVNodeRegistry(msg.sender).CLUSTER_SIZE() / 2) +
                getPermissionlessOperatorShare(
                    operatorShare - collateralETH,
                    rewards,
                    staderConfig.getStakedEthPerNode(),
                    ISSVNodeRegistry(msg.sender)
                );
        }

        if (operatorShare < penaltyAmount) {
            //slash SD of permissionless operators
            ISDCollateral(staderConfig.getSDCollateral()).slashSSVOperatorSD(poolId, validatorId, operatorIds);
            penaltyAmount = operatorShare;
        }
        uint256 userShare = userSharePrelim + penaltyAmount;

        if (penaltyAmount >= ISSVNodeRegistry(msg.sender).CLUSTER_SIZE() * permissionedOperatorShare) {
            permissionlessOperatorShare -=
                (penaltyAmount - (ISSVNodeRegistry(msg.sender).CLUSTER_SIZE() / 2) * permissionedOperatorShare) /
                2;
            permissionedOperatorShare = 0;
        } else {
            permissionedOperatorShare -= penaltyAmount / ISSVNodeRegistry(msg.sender).CLUSTER_SIZE();
            permissionlessOperatorShare -= penaltyAmount / ISSVNodeRegistry(msg.sender).CLUSTER_SIZE();
        }

        // Final settlement
        vaultSettleStatus = true;
        IPenalty(staderConfig.getPenaltyContract()).markValidatorSettled(poolId, validatorId);
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        UtilLib.sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        for (uint8 i; i < totalOperators; i++) {
            (bool operatorType, , , address operatorAddress, , , ) = ISSVNodeRegistry(msg.sender).operatorStructById(
                operatorIds[i]
            );
            if (operatorType) {
                IOperatorRewardsCollector(staderConfig.getOperatorRewardsCollector()).depositFor{
                    value: permissionedOperatorShare
                }(operatorAddress);
            } else {
                IOperatorRewardsCollector(staderConfig.getOperatorRewardsCollector()).depositFor{
                    value: permissionlessOperatorShare
                }(operatorAddress);
            }
        }
        emit SettledFunds(userShare, operatorShare, protocolShare);
    }

    function calculateValidatorWithdrawalShare(uint8 _poolId, IStaderConfig _staderConfig)
        public
        view
        returns (
            uint256 userShare,
            uint256 operatorShare,
            uint256 protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = _staderConfig.getStakedEthPerNode();
        uint256 collateralETH = ISSVNodeRegistry(msg.sender).getCollateralETH();
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 contractBalance = address(this).balance;

        uint256 totalRewards;

        if (contractBalance <= usersETH) {
            userShare = contractBalance;
            return (userShare, operatorShare, protocolShare);
        } else if (contractBalance <= TOTAL_STAKED_ETH) {
            userShare = usersETH;
            operatorShare = contractBalance - userShare;
            return (userShare, operatorShare, protocolShare);
        } else {
            totalRewards = contractBalance - TOTAL_STAKED_ETH;
            operatorShare = collateralETH;
            userShare = usersETH;
        }
        if (totalRewards > 0) {
            (uint256 userReward, uint256 operatorReward, uint256 protocolReward) = IPoolUtils(
                _staderConfig.getPoolUtils()
            ).calculateRewardShare(_poolId, totalRewards);
            userShare += userReward;
            operatorShare += operatorReward;
            protocolShare += protocolReward;
        }
    }

    // HELPER METHODS

    function getUpdatedPenaltyAmount(uint256 _validatorId, IStaderConfig _staderConfig) internal returns (uint256) {
        (, bytes memory pubkey, , , , , , ) = ISSVNodeRegistry(msg.sender).validatorRegistry(_validatorId);
        bytes[] memory pubkeyArray = new bytes[](1);
        pubkeyArray[0] = pubkey;
        IPenalty(_staderConfig.getPenaltyContract()).updateTotalPenaltyAmount(pubkeyArray);
        return IPenalty(_staderConfig.getPenaltyContract()).totalPenaltyAmount(pubkey);
    }

    function getPermissionedOperatorShare(
        uint256 operatorShare,
        uint256 rewards,
        uint256 ETH_PER_NODE,
        ISSVNodeRegistry nodeRegistry
    ) internal view returns (uint256) {
        return
            (operatorShare - (rewards * nodeRegistry.getCollateralETH()) / ETH_PER_NODE) / nodeRegistry.CLUSTER_SIZE();
    }

    function getPermissionlessOperatorShare(
        uint256 operatorShare,
        uint256 rewards,
        uint256 ETH_PER_NODE,
        ISSVNodeRegistry nodeRegistry
    ) internal view returns (uint256) {
        return
            (operatorShare + (rewards * nodeRegistry.getCollateralETH()) / ETH_PER_NODE) / nodeRegistry.CLUSTER_SIZE();
    }
}
