// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/interfaces/ISDUtilityPool.sol';

contract SDUtilityPoolMock {
    function getUtilizerLatestBalance(address) external pure returns (uint256) {
        return 0;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return 50;
    }

    function getUserData(address) external pure returns (UserData memory) {
        return UserData(0, 0, 0, 0);
    }

    function getOperatorLiquidation(address) external pure returns (OperatorLiquidation memory) {
        return OperatorLiquidation(0, 0, 0, false, false, address(0));
    }

    function completeLiquidation() external pure {}
}
