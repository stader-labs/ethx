// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract SDCollateralMock {
    event SDWithdrawn(address indexed operator, uint256 sdAmount);
    event SDRepaid(address operator, uint256 repayAmount);

    function hasEnoughSDCollateral(
        address,
        uint8,
        uint256
    ) external pure returns (bool) {
        return true;
    }

    function slashValidatorSD(uint256, uint8) external {}

    function getOperatorInfo(address)
        external
        pure
        returns (
            uint8,
            uint256,
            uint256
        )
    {
        return (1, 1, 1);
    }

    function convertSDToETH(uint256 _sdAmount) external pure returns (uint256) {
        return _sdAmount / 10000;
    }

    function convertETHToSD(uint256 _ethAmount) external pure returns (uint256) {
        return _ethAmount * 10000;
    }

    function operatorUtilizedSDBalance(address) external pure returns (uint256) {
        return 0;
    }

    function depositSDFromUtilityPool(address, uint256) external {}

    function reduceUtilizedSDPosition(address, uint256) external {}

    function withdrawOnBehalf(uint256 _requestedSD, address _operator) external {
        emit SDRepaid(_operator, _requestedSD);
        emit SDWithdrawn(_operator, _requestedSD);
    }
}
