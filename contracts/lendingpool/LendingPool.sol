// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import '../interfaces/ILendingPool.sol';

contract LendingPool is ILendingPool, AccessControlUpgradeable { 

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function deposit(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function claim(uint256 index) external override returns (uint256) {
        return 0;
    }
}