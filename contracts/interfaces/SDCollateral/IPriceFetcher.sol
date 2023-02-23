// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPriceFetcher {
    /// @dev price is in wei of usdc
    /// hence divide the price returned, by ( 10 ** 6 ) as usdc.decimals() == 6
    function getSDPriceInUSD() external view returns (uint256);

    /// @dev price is in wei of usdc
    /// hence divide the price returned, by ( 10 ** 6 ) as usdc.decimals() == 6
    function getEthPriceInUSD() external view returns (uint256);
}
