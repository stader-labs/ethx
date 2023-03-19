// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderConfig is Initializable, AccessControlUpgradeable {
    uint256 public totalStakedEth;

    address public treasury;
    address public stakePoolManager;

    function initialize(address _admin) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // SETTERS

    function updateTotalStakedEth(uint256 _totalStakedEth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        totalStakedEth = _totalStakedEth;
    }

    function updateTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakePoolManager = _stakePoolManager;
    }
}
