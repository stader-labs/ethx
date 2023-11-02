// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import '../interfaces/ILendingPool.sol';
import '../interfaces/IIncentiveController.sol';
import '../interfaces/ILendingPoolToken.sol';

contract LendingPool is ILendingPool, AccessControlUpgradeable {
    IIncentiveController public incentiveController;
    ILendingPoolToken public lendingPoolToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function deposit(uint256 amount) external override returns (uint256) {
        incentiveController.onDeposit(msg.sender);
        lendingPoolToken.mint(msg.sender, amount);
        return 0;
    }

    function requestWithdraw(uint256 amount) external override returns (uint256) {
        incentiveController.claim(msg.sender);
        lendingPoolToken.burn(msg.sender, amount);
        return 0;
    }

    function claim(uint256 index) external override returns (uint256) {
        incentiveController.claim(msg.sender);
        return 0;
    }

    function borrow(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function repay(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function liquidationCall(address account) external override returns (uint256) {
        return 0;
    }

    function claimLiquidation(uint256 index) external override returns (uint256) {
        return 0;
    }

    function getUserData(address account) external override view returns (UserData memory) {
        return UserData(0, 0, 0, 0);
    }
}