//SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

contract PriceFetcher {
    address public sdUSDCPool;
    address public ethUSDCPool;
    uint32 public twapInterval;

    /**
     * @notice Check for zero address
     * @dev Modifier
     * @param _address the address to check
     */
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    constructor(
        uint32 _twapInterval,
        address _sdUSDCPool,
        address _ethUSDCPool
    ) checkZeroAddress(_sdUSDCPool) checkZeroAddress(_ethUSDCPool) {
        twapInterval = _twapInterval;
        sdUSDCPool = _sdUSDCPool;
        ethUSDCPool = _ethUSDCPool;
    }

    function getSDPriceInUSD() public view returns (uint256 sdPrice) {
        uint160 sqrtPriceX96 = _getSqrtTwapX96(sdUSDCPool, twapInterval);
        return _sqrtPriceX96ToUint(sqrtPriceX96);
    }

    function getEthPriceInUSD() public view returns (uint256 ethPrice) {
        uint160 sqrtPriceX96 = _getSqrtTwapX96(ethUSDCPool, twapInterval);
        return _sqrtPriceX96ToUint(sqrtPriceX96);
    }

    function _getSqrtTwapX96(
        address _uniswapV3Pool,
        uint32 _twapInterval
    ) internal view returns (uint160 sqrtPriceX96) {
        if (_twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = _twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(_uniswapV3Pool).observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / _twapInterval)
            );
        }
    }

    function _sqrtPriceX96ToUint(uint160 _sqrtPriceX96) internal pure returns (uint256) {
        uint256 numerator1 = uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96);
        uint256 numerator2 = 1e18;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }
}
