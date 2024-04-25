// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Need to import ProxyAdmin within contracts folder so `hardhat compile` can find it and compile it
// The artifact of ProxyAdmin needs to be built so as to be used within scripts/safe-scripts
