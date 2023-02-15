// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../contracts/interfaces/ISDStaking.sol';
import '../contracts/interfaces/IPriceFetcher.sol';

contract SDCollateral is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct PoolThresholdInfo {
        uint256 lower;
        uint256 upper;
        string units;
    }

    IERC20 public sdERC20;
    IERC20 public xsdERC20;

    address public sdStakingContractAddr;
    IPriceFetcher public priceFetcher;

    uint256 public totalShares;
    uint256 public totalXSDCollateral;
    // TODO: Manoj we can instead use xsdBalnce(address(this))

    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
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
        address _xsdERC20Addr,
        address _priceFetcherAddr,
        address _sdStakingContractAddr
    )
        external
        initializer
        checkZeroAddress(_admin)
        checkZeroAddress(_sdERC20Addr)
        checkZeroAddress(_xsdERC20Addr)
        checkZeroAddress(_priceFetcherAddr)
        checkZeroAddress(_sdStakingContractAddr)
    {
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);

        sdERC20 = IERC20(_sdERC20Addr);
        xsdERC20 = IERC20(_xsdERC20Addr);
        priceFetcher = IPriceFetcher(_priceFetcherAddr);
        sdStakingContractAddr = _sdStakingContractAddr;
    }

    /**
     * @param _xsdAmount xSD Token Amount to Deposit
     * @dev sender should approve this contract for spending xSD
     */
    function depositXSDAsCollateral(uint256 _xsdAmount) external {
        address operator = msg.sender;
        totalXSDCollateral += _xsdAmount;

        uint256 numShares = convertXSDToShares(_xsdAmount);
        totalShares += numShares;
        operatorShares[operator] += numShares;

        // TODO: Manoj check if the below line could be moved to start of this method
        xsdERC20.safeTransferFrom(operator, address(this), _xsdAmount);
    }

    /**
     * @param _sdAmount xSD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external nonReentrant {
        address operator = msg.sender;
        uint256 xsdAmount = _stakeSD(operator, _sdAmount);

        totalXSDCollateral += xsdAmount;

        uint256 numShares = convertXSDToShares(xsdAmount);
        totalShares += numShares;
        operatorShares[operator] += numShares;
    }

    function withdraw(address _operator, uint256 _xsdAmountToWithdraw) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(5 == 2, 'wip');

        totalXSDCollateral -= _xsdAmountToWithdraw;

        uint256 numShares = convertXSDToShares(_xsdAmountToWithdraw);
        operatorShares[_operator] -= numShares;
        totalShares -= numShares;

        xsdERC20.safeTransfer(payable(_operator), _xsdAmountToWithdraw);
    }

    // function addRewards(uint256 _xsdAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     totalXSDCollateral += _xsdAmount;
    //     xsdERC20.safeTransferFrom(msg.sender, address(this), _xsdAmount);
    // }

    // SETTERS

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _lower,
        uint256 _upper,
        string memory _units
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        poolThresholdbyPoolId[_poolId] = PoolThresholdInfo({lower: _lower, upper: _upper, units: _units});
    }

    // GETTERS

    function hasEnoughXSDCollateral(address _operator, uint8 _poolId) public view returns (bool) {
        uint256 numShares = operatorShares[_operator];
        uint256 xsdBalance = convertSharesToXSD(numShares);
        return _checkPoolThreshold(_poolId, xsdBalance);
    }

    // HELPER FUNCTIONS

    function _checkPoolThreshold(uint8 _poolId, uint256 _xsdBalance) internal view returns (bool) {
        uint256 sdBalance = convertXSDToSD(_xsdBalance);
        uint256 eqEthBalance = convertSDToETH(sdBalance);

        require(bytes(poolThresholdbyPoolId[_poolId].units).length > 0, 'invalid poolId');
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];
        return (eqEthBalance >= poolThresholdInfo.lower && eqEthBalance <= poolThresholdInfo.upper);
    }

    function _stakeSD(address _operator, uint256 _sdAmount) internal returns (uint256 xsdAmount) {
        uint256 xsdBalanceBefore = xsdERC20.balanceOf(address(this));
        sdERC20.safeTransferFrom(_operator, address(this), _sdAmount);
        ISDStaking(sdStakingContractAddr).stake(_sdAmount);
        uint256 xsdBalanceAfter = xsdERC20.balanceOf(address(this));
        xsdAmount = xsdBalanceAfter - xsdBalanceBefore;
    }

    function convertXSDToSD(uint256 _xsdAmount) public view returns (uint256) {
        uint256 er = ISDStaking(sdStakingContractAddr).getExchangeRate(); // 1 xSD = er/1e18 SD

        return (er * _xsdAmount) / 1e18;
    }

    function convertSDToXSD(uint256 _sdAmount) public view returns (uint256) {
        uint256 er = ISDStaking(sdStakingContractAddr).getExchangeRate(); // 1 xSD = er/1e18 SD

        return (_sdAmount * 1e18) / er;
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

    function convertXSDToShares(uint256 _xsdAmount) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalXSDCollateral_ = totalXSDCollateral == 0 ? 1 : totalXSDCollateral;
        return (_xsdAmount * totalShares_) / totalXSDCollateral_;
    }

    function convertSharesToXSD(uint256 _numShares) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalXSDCollateral_ = totalXSDCollateral == 0 ? 1 : totalXSDCollateral;
        return (_numShares * totalXSDCollateral_) / totalShares_;
    }
}
