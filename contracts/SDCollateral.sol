// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../contracts/interfaces/ISDStaking.sol';
import '../contracts/interfaces/IPriceFetcher.sol';

contract SDCollateral is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    struct PoolThresholdInfo {
        uint256 lower;
        uint256 withdrawThreshold;
        uint256 upper;
        string units;
    }
    bytes32 public constant WHITELISTED_CONTRACT = keccak256('WHITELISTED_CONTRACT');

    IERC20 public sdERC20;
    IPriceFetcher public priceFetcher;

    uint256 public totalShares;
    uint256 public totalSDCollateral;
    // TODO: Manoj we can instead use sdBalnce(address(this))

    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint8) public poolIdByOperator;
    mapping(address => uint256) public operatorShares;

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
        address _admin,
        address _sdERC20Addr,
        address _priceFetcherAddr
    ) external initializer checkZeroAddress(_admin) checkZeroAddress(_sdERC20Addr) checkZeroAddress(_priceFetcherAddr) {
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);

        sdERC20 = IERC20(_sdERC20Addr);
        priceFetcher = IPriceFetcher(_priceFetcherAddr);
    }

    /**
     * @param _sdAmount SD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external {
        address operator = msg.sender;
        totalSDCollateral += _sdAmount;

        uint256 numShares = convertSDToShares(_sdAmount);
        totalShares += numShares;
        operatorShares[operator] += numShares;

        // TODO: Manoj check if the below line could be moved to start of this method
        require(sdERC20.transferFrom(operator, address(this), _sdAmount), 'sd transfer failed');
    }

    function withdraw(uint256 _requestedSD) external {
        address operator = msg.sender;
        uint256 numShares = operatorShares[operator];
        uint256 sdBalance = convertSharesToSD(numShares);

        uint8 poolId = poolIdByOperator[operator];
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        uint256 validatorCount = 0; // TODO: Manoj :poolFactory.getPoolContract(poolId).getOnlineValidatorCount(operator);
        uint256 withdrawableSD = sdBalance - convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);

        require(_requestedSD <= withdrawableSD, 'withdraw less SD');

        totalSDCollateral -= _requestedSD;
        operatorShares[operator] -= numShares;
        totalShares -= numShares;

        require(sdERC20.transfer(payable(operator), _requestedSD), 'sd transfer failed');
    }

    // function addRewards(uint256 _xsdAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     totalXSDCollateral += _xsdAmount;
    //     xsdERC20.safeTransferFrom(msg.sender, address(this), _xsdAmount);
    // }

    // SETTERS

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _lower,
        uint256 _withdrawThreshold,
        uint256 _upper,
        string memory _units
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lower <= _withdrawThreshold && _withdrawThreshold <= _upper, 'invalid limits');

        poolThresholdbyPoolId[_poolId] = PoolThresholdInfo({
            lower: _lower,
            withdrawThreshold: _withdrawThreshold,
            upper: _upper,
            units: _units
        });
    }

    function updatePoolIdForOperator(
        uint8 _poolId,
        address _operator
    ) public onlyRole(WHITELISTED_CONTRACT) checkZeroAddress(_operator) {
        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        poolIdByOperator[_operator] = _poolId;
    }

    // GETTERS

    function hasEnoughXSDCollateral(
        address _operator,
        uint8 _poolId,
        uint32 _numValidators
    ) public view returns (bool) {
        uint256 numShares = operatorShares[_operator];
        uint256 sdBalance = convertSharesToSD(numShares);
        return _checkPoolThreshold(_poolId, sdBalance, _numValidators);
    }

    // HELPER FUNCTIONS

    function _checkPoolThreshold(
        uint8 _poolId,
        uint256 _sdBalance,
        uint32 _numValidators
    ) internal view returns (bool) {
        uint256 eqEthBalance = convertSDToETH(_sdBalance);

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];
        return (eqEthBalance >= (poolThresholdInfo.lower * _numValidators) &&
            eqEthBalance <= (poolThresholdInfo.upper * _numValidators));
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
