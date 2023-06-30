// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

contract StakePoolManagerMock {
    function receiveEthFromAuction() external payable {}

    function receiveWithdrawVaultUserShare() external payable {}

    function receiveExecutionLayerRewards() external payable {}

    function receiveExcessEthFromPool(uint8) external payable {}

    function previewWithdraw(uint256 _shares) external pure returns (uint256) {
        return _shares;
    }

    function getExchangeRate() external pure returns (uint256) {
        return 0.8 * 10**18;
    }

    function transferETHToUserWithdrawManager(uint256 _amount) external {
        (bool success, ) = payable(msg.sender).call{value: _amount}('');
    }
}
