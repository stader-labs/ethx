// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ITWAPGetter {
    /**
     * @notice converts _baseToken -> _quoteToken
     * @return quoteAmount Amount of _quoteToken eq to 1 _baseToken
     * @dev quoteAmount is in wei of _quoteToken
     * hence divide the quoteAmount returned, by { 10 ** _quoteToken.decimals() }
     */
    function getPrice(
        address _uniswapV3Pool,
        address _baseToken,
        address _quoteToken,
        uint32 _twapInterval
    ) external view returns (uint256 quoteAmount);
}
