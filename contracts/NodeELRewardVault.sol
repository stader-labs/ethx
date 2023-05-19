// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IPoolUtils.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/ITokenDropBox.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract NodeELRewardVault is INodeELRewardVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    IStaderConfig public override staderConfig;
    uint8 public override poolId; // No Setter as this is supposed to be set once
    uint256 public override operatorId; // No Setter as this is supposed to be set once

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint8 _poolId,
        uint256 _operatorId,
        address _staderConfig
    ) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __ReentrancyGuard_init();

        poolId = _poolId;
        operatorId = _operatorId;
        staderConfig = IStaderConfig(_staderConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function withdraw() external override nonReentrant {
        uint256 totalRewards = address(this).balance;
        if (totalRewards == 0) {
            revert NotEnoughRewardToWithdraw();
        }
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = IPoolUtils(staderConfig.getPoolUtils())
            .calculateRewardShare(poolId, totalRewards);

        // Distribute rewards
        bool success;
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveExecutionLayerRewards{value: userShare}();

        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderConfig.getStaderTreasury()).call{value: protocolShare}('');
        if (!success) {
            revert ETHTransferFailed(staderConfig.getStaderTreasury(), protocolShare);
        }

        address operator = UtilLib.getOpAddrByOpId(poolId, operatorId, staderConfig);
        ITokenDropBox(staderConfig.getTokenDropBox()).depositFor{value: operatorShare}(operator);

        emit Withdrawal(protocolShare, operatorShare, userShare);
    }

    // SETTERS
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
