// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';

contract StaderWithdrawVault is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Pool information
    uint8 public poolId;
    address public poolFactory;

    // Recipients
    address payable public nodeRecipient;
    address payable public staderTreasury;
    address payable public staderStakePoolsManager;

    uint256 public constant TOTAL_STAKED_ETH = 32 ether;

    function initialize(
        address _admin,
        address payable _nodeRecipient,
        address payable _staderTreasury,
        address payable _staderStakePoolsManager,
        address _poolFactory,
        uint8 _poolId
    ) external initializer {
        Address.checkNonZeroAddress(_admin);
        Address.checkNonZeroAddress(_nodeRecipient);
        Address.checkNonZeroAddress(_staderTreasury);
        Address.checkNonZeroAddress(_staderStakePoolsManager);
        Address.checkNonZeroAddress(_poolFactory);

        __AccessControl_init_unchained();
        __ReentrancyGuard_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        staderTreasury = _staderTreasury;
        nodeRecipient = _nodeRecipient;
        staderStakePoolsManager = _staderStakePoolsManager;
        poolFactory = _poolFactory;
        poolId = _poolId;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev skimmed rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        // emit ETHReceived(msg.value);
    }

    function distributeRewards(bool _withdrawStatus) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(_withdrawStatus);

        bool success;

        // Distribute rewards
        IStaderStakePoolManager(staderStakePoolsManager).receiveWithdrawVaultUserShare{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderTreasury).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        // slither-disable-next-line arbitrary-send-eth

        if (operatorShare > 0) {
            (success, ) = payable(nodeRecipient).call{value: operatorShare}('');
            require(success, 'Operator share transfer failed');
        }
    }

    function _calculateRewardShare(
        bool _withdrawStatus
    ) internal view returns (uint256 _userShare, uint256 _operatorShare, uint256 _protocolShare) {
        uint256 collateralETH = getCollateralETH();
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeePercent = getProtocolFeePercent();
        uint256 operatorFeePercent = getOperatorFeePercent();

        uint256 _totalRewards = address(this).balance;
        if (_withdrawStatus) {
            if (address(this).balance < usersETH) {
                // if less than 28 eth, send all to users
                _userShare = address(this).balance;
                _operatorShare = 0;
                _protocolShare = 0;
                return (_userShare, _operatorShare, _protocolShare);
            } else if (address(this).balance >= usersETH && address(this).balance < collateralETH) {
                // between 28 to 32, send 28 to user, rest to operator
                _userShare = usersETH;
                _operatorShare = address(this).balance - _userShare;
                _protocolShare = 0;
                return (_userShare, _operatorShare, _protocolShare);
            } else {
                // more than 32, 28 to user, 4 to operator, and split rewards as usual
                _totalRewards = address(this).balance - TOTAL_STAKED_ETH;
                _operatorShare = collateralETH;
                _userShare = usersETH;
            }
        } else {
            _totalRewards = address(this).balance;
        }

        uint256 _userShareBeforeCommision = (usersETH * _totalRewards) / TOTAL_STAKED_ETH;
        _userShare += ((100 - protocolFeePercent - operatorFeePercent) * _userShareBeforeCommision) / 100;

        _operatorShare += (collateralETH * _totalRewards) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeePercent * _userShareBeforeCommision) / 100;

        _protocolShare = (protocolFeePercent * _userShareBeforeCommision) / 100; // or _totalRewards - _userShare - _operatorShare
    }

    // getters

    function getProtocolFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getProtocolFeePercent(poolId);
    }

    // should return 0, for permissioned NOs
    function getOperatorFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getOperatorFeePercent(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(poolFactory).getCollateralETH(poolId);
    }
}
