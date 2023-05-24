// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract PermissionlessPoolMock {
    function preDepositOnBeaconChain(
        bytes[] calldata _pubkey,
        bytes[] calldata _preDepositSignature,
        uint256 _operatorId,
        uint256 _operatorTotalKeys
    ) external payable {}

    function receiveRemainingCollateralETH() external payable {}
}
