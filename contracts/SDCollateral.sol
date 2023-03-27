// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../contracts/interfaces/IPoolFactory.sol';
import '../contracts/interfaces/IStaderConfig.sol';
import '../contracts/interfaces/SDCollateral/IPriceFetcher.sol';
import '../contracts/interfaces/SDCollateral/ISDCollateral.sol';
import '../contracts/interfaces/SDCollateral/ISingleSwap.sol';

import './library/Address.sol';

contract SDCollateral is
    ISDCollateral,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct PoolThresholdInfo {
        uint256 minThreshold;
        uint256 withdrawThreshold;
        string units;
    }
    bytes32 public constant WHITELISTED_CONTRACT = keccak256('WHITELISTED_CONTRACT');

    IStaderConfig public staderConfig;
    IPriceFetcher public priceFetcher;
    ISingleSwap public swapUtil;

    uint256 public totalShares;
    uint256 public totalSDCollateral;
    // TODO: Manoj we can instead use sdBalnce(address(this))

    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint8) public poolIdByOperator;
    mapping(address => uint256) public operatorShares;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _staderConfig,
        address _priceFetcherAddr,
        address _swapUtil
    ) external initializer {
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_priceFetcherAddr);
        Address.checkNonZeroAddress(_swapUtil);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        priceFetcher = IPriceFetcher(_priceFetcherAddr);
        swapUtil = ISingleSwap(_swapUtil);

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @param _sdAmount SD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external {
        address operator = msg.sender;
        uint256 numShares = convertSDToShares(_sdAmount);

        totalSDCollateral += _sdAmount;
        totalShares += numShares;
        operatorShares[operator] += numShares;

        // TODO: Manoj check if the below line could be moved to start of this method
        bool success = IERC20(staderConfig.getStaderToken()).transferFrom(operator, address(this), _sdAmount);
        require(success, 'sd transfer failed');
    }

    function withdraw(uint256 _requestedSD) external {
        address operator = msg.sender;
        uint256 numShares = operatorShares[operator];
        uint256 sdBalance = convertSharesToSD(numShares);

        uint8 poolId = poolIdByOperator[operator];
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        // TODO: Manoj update startIndex, endIndex
        uint256 validatorCount = IPoolFactory(staderConfig.getPoolFactory()).getOperatorTotalNonTerminalKeys(
            poolId,
            operator,
            0,
            1000
        );
        uint256 withdrawableSD = sdBalance - convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);

        require(_requestedSD <= withdrawableSD, 'withdraw less SD');

        totalSDCollateral -= _requestedSD;
        operatorShares[operator] -= numShares;
        totalShares -= numShares;

        bool success = IERC20(staderConfig.getStaderToken()).transfer(payable(operator), _requestedSD);
        require(success, 'sd transfer failed');
    }

    // sends eth (not weth) to msg.sender
    // TODO: discuss if we need to send weth (instead of eth), sending weth is easier.
    function swapSDToETH(uint256 _sdAmount) external {
        uint256 ethOutMinimum = convertSDToETH(_sdAmount);
        swapUtil.swapExactInputForETH(staderConfig.getStaderToken(), _sdAmount, ethOutMinimum, msg.sender);
    }

    // function addRewards(uint256 _xsdAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     totalXSDCollateral += _xsdAmount;
    //     xsdERC20.safeTransferFrom(msg.sender, address(this), _xsdAmount);
    // }

    // SETTERS

    function updateSwapUtil(address _swapUtil) external {
        Address.checkNonZeroAddress(_swapUtil);
        swapUtil = ISingleSwap(_swapUtil);
    }

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_minThreshold <= _withdrawThreshold, 'invalid limits');

        poolThresholdbyPoolId[_poolId] = PoolThresholdInfo({
            minThreshold: _minThreshold,
            withdrawThreshold: _withdrawThreshold,
            units: _units
        });
    }

    function updatePoolIdForOperator(uint8 _poolId, address _operator) public onlyRole(WHITELISTED_CONTRACT) {
        Address.checkNonZeroAddress(_operator);
        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        poolIdByOperator[_operator] = _poolId;
    }

    // GETTERS

    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidators
    ) external view returns (bool) {
        uint256 numShares = operatorShares[_operator];
        uint256 sdBalance = convertSharesToSD(numShares);
        return _checkPoolThreshold(_poolId, sdBalance, _numValidators);
    }

    function getOperatorSDBalance(address _operator) public view returns (uint256) {
        uint256 numShares = operatorShares[_operator];
        return convertSharesToSD(numShares);
    }

    function getMinimumAmountToDeposit(
        address _operator,
        uint8 _poolId,
        uint32 _numValidators
    ) public view returns (uint256) {
        uint256 sdBalance = getOperatorSDBalance(_operator);

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];

        uint256 minThresholdInSD = convertETHToSD(poolThresholdInfo.minThreshold);
        minThresholdInSD *= _numValidators;

        return (sdBalance >= minThresholdInSD ? 0 : minThresholdInSD);
    }

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) public view returns (uint256) {
        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');

        uint256 ethAmount = convertSDToETH(_sdAmount);
        return ethAmount / poolThresholdbyPoolId[_poolId].minThreshold;
    }

    // HELPER FUNCTIONS

    function _checkPoolThreshold(
        uint8 _poolId,
        uint256 _sdBalance,
        uint256 _numValidators
    ) internal view returns (bool) {
        uint256 eqEthBalance = convertSDToETH(_sdBalance);

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];
        return (eqEthBalance >= (poolThresholdInfo.minThreshold * _numValidators));
    }

    function convertSDToETH(uint256 _sdAmount) public view returns (uint256) {
        uint256 sdPriceInUSD = priceFetcher.getSDPriceInUSD();
        uint256 ethPriceInUSD = priceFetcher.getEthPriceInUSD();

        return (_sdAmount * sdPriceInUSD) / ethPriceInUSD;
    }

    function convertETHToSD(uint256 _ethAmount) public view returns (uint256) {
        uint256 sdPriceInUSD = priceFetcher.getSDPriceInUSD();
        uint256 ethPriceInUSD = priceFetcher.getEthPriceInUSD();
        return (_ethAmount * ethPriceInUSD) / sdPriceInUSD;
    }

    function convertSDToShares(uint256 _sdAmount) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalSDCollateral_ = totalSDCollateral == 0 ? 1 : totalSDCollateral;
        return (_sdAmount * totalShares_) / totalSDCollateral_;
    }

    function convertSharesToSD(uint256 _numShares) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalSDCollateral_ = totalSDCollateral == 0 ? 1 : totalSDCollateral;
        return (_numShares * totalSDCollateral_) / totalShares_;
    }
}
