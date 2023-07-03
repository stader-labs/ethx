// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/StaderConfig.sol';

contract PermissionedPoolMock {
    StaderConfig staderConfig;

    constructor(address _staderConfigAddr) {
        staderConfig = StaderConfig(_staderConfigAddr);
    }

    function receiveInsuranceFund() external payable {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.STADER_INSURANCE_FUND());
    }

    function transferETHOfDefectiveKeysToSSPM(uint256) external {}

    function fullDepositOnBeaconChain(bytes[] calldata _pubkey) external {}
}
