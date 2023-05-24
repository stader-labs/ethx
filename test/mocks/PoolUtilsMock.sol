// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './NodeRegistryMock.sol';
import '../../contracts/StaderConfig.sol';

contract PoolUtilsMock {
    NodeRegistryMock public nodeRegistry;
    uint256 operatorTotalNonTerminalKeys;
    StaderConfig staderConfig;

    constructor(address _staderConfigAddr) {
        nodeRegistry = new NodeRegistryMock();
        operatorTotalNonTerminalKeys = 5;
        staderConfig = StaderConfig(_staderConfigAddr);
    }

    function getOperatorPoolId(address) external pure returns (uint8) {
        return 1;
    }

    // function getValidatorPoolId(bytes calldata) external pure returns (uint8) {
    //     return 1;
    // }

    function getNodeRegistry(uint8) public view returns (address) {
        return address(nodeRegistry);
    }

    function getOperatorTotalNonTerminalKeys(
        uint8,
        address,
        uint256,
        uint256
    ) public view returns (uint256) {
        return operatorTotalNonTerminalKeys;
    }

    function updateOperatorTotalNonTerminalKeys(bool increase, uint256 numUpdate) public {
        if (increase) {
            operatorTotalNonTerminalKeys += numUpdate;
        } else {
            operatorTotalNonTerminalKeys -= numUpdate;
        }
    }

    function calculateRewardShare(uint8 _poolId, uint256 _totalRewards)
        external
        view
        returns (
            uint256 userShare,
            uint256 operatorShare,
            uint256 protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH(_poolId);
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeeBps = getProtocolFee(_poolId);
        uint256 operatorFeeBps = getOperatorFee(_poolId);

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        protocolShare = (protocolFeeBps * _userShareBeforeCommision) / staderConfig.getTotalFee();

        operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        operatorShare += (operatorFeeBps * _userShareBeforeCommision) / staderConfig.getTotalFee();

        userShare = _totalRewards - protocolShare - operatorShare;
    }

    function getCollateralETH(uint8 _poolId) public pure returns (uint256) {
        if (_poolId == 2) return 0; // permissioned pool
        return 4 ether;
    }

    function getProtocolFee(uint8) public pure returns (uint256) {
        return 500;
    }

    function getOperatorFee(uint8) public pure returns (uint256) {
        return 500;
    }
}
