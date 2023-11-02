// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ILendingPoolToken {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}
