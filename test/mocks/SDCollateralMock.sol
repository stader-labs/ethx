// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract SDCollateralMock {
    function hasEnoughSDCollateral(
        address,
        uint8,
        uint256
    ) external pure returns (bool) {
        return true;
    }

    function slashValidatorSD(uint256, uint8) external {}
}
