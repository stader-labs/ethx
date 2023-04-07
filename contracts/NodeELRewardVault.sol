// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IStaderStakePoolManager.sol';

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
        AddressLib.checkNonZeroAddress(_staderConfig);

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
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = calculateRewardShare(address(this).balance);

        // TODO: Reminder Manoj is it safe to distribute rewards to all in a single method ?
        // Distribute rewards
        bool success;
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveExecutionLayerRewards{value: userShare}();

        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderConfig.getStaderTreasury()).call{value: protocolShare}('');
        if (!success) {
            revert ETHTransferFailed(staderConfig.getStaderTreasury(), protocolShare);
        }

        // slither-disable-next-line arbitrary-send-eth
        (success, ) = getNodeRecipient().call{value: operatorShare}('');
        if (!success) {
            revert ETHTransferFailed(getNodeRecipient(), operatorShare);
        }

        emit Withdrawal(protocolShare, operatorShare, userShare);
    }

    function calculateRewardShare(uint256 _totalRewards)
        public
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        if (_totalRewards == 0) {
            return (0, 0, 0);
        }

        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH();
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeeBps = getProtocolFeeBps();
        uint256 operatorFeeBps = getOperatorFeeBps();

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        _protocolShare = (protocolFeeBps * _userShareBeforeCommision) / 10000;

        _operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeeBps * _userShareBeforeCommision) / 10000;

        _userShare = _totalRewards - _protocolShare - _operatorShare;
    }

    function getProtocolFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getProtocolFee(poolId);
    }

    function getOperatorFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getOperatorFee(poolId);
    }

    function getCollateralETH() internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getCollateralETH(poolId);
    }

    //TODO sanjay move to node registry
    function getNodeRecipient() internal view returns (address payable) {
        address nodeRegistry = IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId);
        address payable operatorRewardAddress = INodeRegistry(nodeRegistry).getOperatorRewardAddress(operatorId);
        return operatorRewardAddress;
    }

    // SETTERS

    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
