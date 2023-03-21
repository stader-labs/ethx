// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ISingleSwap {
    // msg.sender must approve this contract to spend tokenIn
    function swapExactInputForETH(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external returns (uint256 amountOut);
}
