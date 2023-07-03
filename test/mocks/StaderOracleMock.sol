// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/interfaces/IStaderOracle.sol';
contract StaderOracleMock {
    function getSDPriceInETH() external pure returns (uint256) {
        return 1e18 / 1600;
    }

        function getExchangeRate() external view returns (ExchangeRate memory _exchangeRate){
            _exchangeRate.totalETHXSupply = 1 ether;
            _exchangeRate.totalETHBalance = 1 ether;
            _exchangeRate.reportingBlockNumber = block.number;
            return _exchangeRate;
        }
 
}
