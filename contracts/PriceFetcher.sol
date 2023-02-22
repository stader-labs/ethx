// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '../contracts/interfaces/ITWAPGetter.sol';

contract PriceFetcher is Initializable {
    address public sdERC20;
    address public usdcERC20;
    address public wethERC20;

    address public wethUSDCPool;
    address public sdUSDCPool;
    ITWAPGetter public twapGetter;
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _sdERC20Addr,
        address _usdcERC20Addr,
        address _wethERC20Addr,
        address _sdUSDCPool,
        address _wethUSDCPool,
        address _twapGetterAddr
    )
        external
        initializer
        checkZeroAddress(_sdERC20Addr)
        checkZeroAddress(_usdcERC20Addr)
        checkZeroAddress(_wethERC20Addr)
        checkZeroAddress(_sdUSDCPool)
        checkZeroAddress(_wethUSDCPool)
        checkZeroAddress(_twapGetterAddr)
    {
        sdERC20 = _sdERC20Addr;
        usdcERC20 = _usdcERC20Addr;
        wethERC20 = _wethERC20Addr;
        wethUSDCPool = _wethUSDCPool;
        sdUSDCPool = _sdUSDCPool;
        twapGetter = ITWAPGetter(_twapGetterAddr);
    }

    function setTwapInterval(uint32 _twapInterval) external {
        twapInterval = _twapInterval;
    }

    function getSDPriceInUSD() external view returns (uint256) {
        return twapGetter.getPrice(sdUSDCPool, sdERC20, usdcERC20, twapInterval);
    }

    function getEthPriceInUSD() external view returns (uint256) {
        return twapGetter.getPrice(wethUSDCPool, wethERC20, usdcERC20, twapInterval);
    }
}
