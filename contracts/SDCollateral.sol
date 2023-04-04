// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../contracts/interfaces/IPoolFactory.sol';
import '../contracts/interfaces/IStaderConfig.sol';
import '../contracts/interfaces/SDCollateral/ISDCollateral.sol';
import '../contracts/interfaces/SDCollateral/IAuction.sol';
import '../contracts/interfaces/IStaderOracle.sol';

import './library/Address.sol';

contract SDCollateral is
    ISDCollateral,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant NODE_REGISTRY_CONTRACT = keccak256('NODE_REGISTRY_CONTRACT');

    IStaderConfig public staderConfig;
    uint256 public totalSDCollateral;
    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint8) private poolIdByOperator;
    mapping(address => uint256) public operatorSDBalance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);

        // max approval to auction contract for spending SD tokens
        IERC20(staderConfig.getStaderToken()).approve(staderConfig.getAuctionContract(), type(uint256).max);
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

        uint8 poolId = getOperatorPoolId(operator);
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        // TODO: Manoj update startIndex, endIndex
        uint256 validatorCount = IPoolFactory(staderConfig.getPoolFactory()).getOperatorTotalNonTerminalKeys(
            poolId,
            operator,
            0,
            1000
        );

        uint256 sdCumulativeThreshold = convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);
        if (sdBalance <= sdCumulativeThreshold) {
            revert InsufficientSDToWithdraw();
        }
        uint256 withdrawableSD = sdBalance - sdCumulativeThreshold;

        require(_requestedSD <= withdrawableSD, 'withdraw less SD');

        totalSDCollateral -= _requestedSD;
        operatorSDBalance[operator] -= _requestedSD;

        bool success = IERC20(staderConfig.getStaderToken()).transfer(payable(operator), _requestedSD);
        require(success, 'sd transfer failed');
    }

    // TODO: proper access control
    function slashSD(address _operator, uint256 _sdToSlash)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 _sdSlashed)
    {
        uint256 sdBalance = operatorSDBalance[_operator];
        _sdSlashed = _sdToSlash;
        if (_sdToSlash > sdBalance) {
            _sdSlashed = sdBalance;
        }
        operatorSDBalance[_operator] -= _sdSlashed;

        // TODO: Manoj research and check if below is a correct solution
        // reduced approval to zero first, to avoid race condition
        IERC20(staderConfig.getStaderToken()).approve(staderConfig.getAuctionContract(), 0);
        IERC20(staderConfig.getStaderToken()).approve(staderConfig.getAuctionContract(), _sdSlashed);

        IAuction(staderConfig.getAuctionContract()).createLot(_sdSlashed);
    }

    // SETTERS

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

    function updatePoolIdForOperator(uint8 _poolId, address _operator) public onlyRole(NODE_REGISTRY_CONTRACT) {
        Address.checkNonZeroAddress(_operator);
        if (_poolId == 0) revert InvalidPoolId();
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }
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
        return (getRemainingSDToBond(_operator, _poolId, _numValidator) == 0);
    }

    function getOperatorPoolId(address _operator) public view returns (uint8 _poolId) {
        _poolId = poolIdByOperator[_operator];
        // TODO: this check is not required as I am checking this while setting
        if (_poolId == 0) revert InvalidPoolId();
    }

    /// @notice returns minimum amount of SD required to onboard _numValidators in a pool
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getMinimumSDToBond(uint8 _poolId, uint256 _numValidator) public view returns (uint256 _minSDToBond) {
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];

        _minSDToBond = convertETHToSD(poolThresholdInfo.minThreshold);
        _minSDToBond *= _numValidator;
    }

    /// @notice returns remaining amount of SD required to onboard _numValidators
    /// @param _operator node operator addr who want to onboard validators
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getRemainingSDToBond(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) public view returns (uint256) {
        uint256 sdBalance = operatorSDBalance[_operator];
        uint256 minSDToBond = getMinimumSDToBond(_poolId, _numValidator);
        return (sdBalance >= minSDToBond ? 0 : minSDToBond - sdBalance);
    }

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) public view returns (uint256) {
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }

        uint256 ethAmount = convertSDToETH(_sdAmount);
        return ethAmount / poolThresholdbyPoolId[_poolId].minThreshold;
    }

    function convertSDToETH(uint256 _sdAmount) public view returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_sdAmount * sdPriceInETH);
    }

    function convertETHToSD(uint256 _ethAmount) public view returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_ethAmount / sdPriceInETH);
    }
}
