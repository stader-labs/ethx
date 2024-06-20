// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;

    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
