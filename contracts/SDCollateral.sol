// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../contracts/interfaces/IPoolFactory.sol';
import '../contracts/interfaces/IStaderConfig.sol';
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
    ISingleSwap public swapUtil;

    uint256 public totalSDCollateral;
    // TODO: Manoj we can instead use sdBalnce(address(this))

    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint8) public poolIdByOperator;
    mapping(address => uint256) public operatorSDBalance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig, address _swapUtil) external initializer {
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_swapUtil);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        swapUtil = ISingleSwap(_swapUtil);

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @param _sdAmount SD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external {
        address operator = msg.sender;

        totalSDCollateral += _sdAmount;
        operatorSDBalance[operator] += _sdAmount;

        // TODO: Manoj check if the below line could be moved to start of this method
        bool success = IERC20(staderConfig.getStaderToken()).transferFrom(operator, address(this), _sdAmount);
        require(success, 'sd transfer failed');
    }

    function withdraw(uint256 _requestedSD) external {
        address operator = msg.sender;
        uint256 sdBalance = operatorSDBalance[operator];

        uint8 poolId = poolIdByOperator[operator];
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        // TODO: Manoj update startIndex, endIndex
        uint256 validatorCount = IPoolFactory(staderConfig.getPoolFactory()).getOperatorTotalNonTerminalKeys(
            poolId,
            operator,
            0,
            1000
        );
        if (sdBalance <= convertETHToSD(poolThreshold.withdrawThreshold * validatorCount)) {
            revert InsufficientSDToWithdraw();
        }
        uint256 withdrawableSD = sdBalance - convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);

        require(_requestedSD <= withdrawableSD, 'withdraw less SD');

        totalSDCollateral -= _requestedSD;
        operatorSDBalance[operator] -= _requestedSD;

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

    // TODO: Manoj Some Contract should execute it, when operator is onboarded to a pool
    function updatePoolIdForOperator(uint8 _poolId, address _operator) public onlyRole(WHITELISTED_CONTRACT) {
        Address.checkNonZeroAddress(_operator);
        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        poolIdByOperator[_operator] = _poolId;
    }

    // GETTERS

    /// @notice checks if operator has enough SD collateral to onboard validators in a specific pool
    /// @param _operator node operator addr who want to onboard validators
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard
    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) external view returns (bool) {
        uint256 sdBalance = operatorSDBalance[_operator];
        uint256 eqEthBalance = convertSDToETH(sdBalance);

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];

        return (eqEthBalance >= (poolThresholdInfo.minThreshold * _numValidator));
    }

    /// @notice returns minimum amount of SD required to onboard _numValidators
    /// @param _operator node operator addr who want to onboard validators
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getMinimumSDToBond(
        address _operator,
        uint8 _poolId,
        uint32 _numValidator
    ) public view returns (uint256) {
        uint256 sdBalance = operatorSDBalance[_operator];

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];

        uint256 minThresholdInSD = convertETHToSD(poolThresholdInfo.minThreshold);
        minThresholdInSD *= _numValidator;

        return (sdBalance >= minThresholdInSD ? 0 : minThresholdInSD - sdBalance);
    }

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) public view returns (uint256) {
        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');

        uint256 ethAmount = convertSDToETH(_sdAmount);
        return ethAmount / poolThresholdbyPoolId[_poolId].minThreshold;
    }

    // TODO: fetch price from oracle
    function convertSDToETH(uint256 _sdAmount) public pure returns (uint256) {
        uint256 sdPriceInUSD = 1;
        uint256 ethPriceInUSD = 1;

        return (_sdAmount * sdPriceInUSD) / ethPriceInUSD;
    }

    // TODO: fetch price from oracle
    function convertETHToSD(uint256 _ethAmount) public pure returns (uint256) {
        uint256 sdPriceInUSD = 1;
        uint256 ethPriceInUSD = 1;
        return (_ethAmount * ethPriceInUSD) / sdPriceInUSD;
    }
}
