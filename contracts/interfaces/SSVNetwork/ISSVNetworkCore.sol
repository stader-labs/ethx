// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ISSVNetworkCore {
    struct Cluster {
        uint32 validatorCount;
        uint64 networkFeeIndex;
        uint64 index;
        bool active;
        uint256 balance;
    }
}
