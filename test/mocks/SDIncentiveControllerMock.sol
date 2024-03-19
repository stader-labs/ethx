// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/interfaces/ISDIncentiveController.sol";

contract SDIncentiveControllerMock {
    function updateRewardForAccount(address) external {}

    function claim(address) external {}
}
