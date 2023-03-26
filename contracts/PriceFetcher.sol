// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import '../contracts/interfaces/SDCollateral/ITWAPGetter.sol';
import '../contracts/interfaces//IStaderConfig.sol';

import './library/Address.sol';

contract PriceFetcher is Initializable, AccessControlUpgradeable {
    address public usdcERC20;
    address public wethUSDCPool;
    address public sdUSDCPool;

    IStaderConfig public staderConfig;
    ITWAPGetter public twapGetter;
    uint32 public twapInterval;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _staderConfig,
        address _usdcERC20Addr,
        address _sdUSDCPool,
        address _wethUSDCPool,
        address _twapGetterAddr
    ) external initializer {
        Address.checkNonZeroAddress(_usdcERC20Addr);
        Address.checkNonZeroAddress(_sdUSDCPool);
        Address.checkNonZeroAddress(_wethUSDCPool);
        Address.checkNonZeroAddress(_twapGetterAddr);

        __AccessControl_init();

        staderConfig = IStaderConfig(_staderConfig);
        usdcERC20 = _usdcERC20Addr;
        wethUSDCPool = _wethUSDCPool;
        sdUSDCPool = _sdUSDCPool;
        twapGetter = ITWAPGetter(_twapGetterAddr);

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getMultiSigAdmin());
    }

    function setTwapInterval(uint32 _twapInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        twapInterval = _twapInterval;
    }

    function getSDPriceInUSD() external view returns (uint256) {
        return twapGetter.getPrice(sdUSDCPool, staderConfig.getStaderToken(), usdcERC20, twapInterval);
    }

    function getEthPriceInUSD() external view returns (uint256) {
        return twapGetter.getPrice(wethUSDCPool, staderConfig.getWethToken(), usdcERC20, twapInterval);
    }
}
