// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/interfaces/IPermissionedPool.sol";

contract StaderInsuranceFundMock {
    function depositFund() external payable {}

    function reimburseUserFund(uint256 _amount) external {
        IPermissionedPool(msg.sender).receiveInsuranceFund{ value: _amount }();
    }
}
