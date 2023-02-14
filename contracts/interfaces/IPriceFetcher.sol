// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPriceFetcher {
    function getSDPriceInUSD() external view returns (uint256);

    function getEthPriceInUSD() external view returns (uint256);
}
