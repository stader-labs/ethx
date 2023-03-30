// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './library/Address.sol';
import '../contracts/interfaces/IStaderStakePoolManager.sol';
import '../contracts/interfaces/IStaderConfig.sol';

contract Auction is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant MANAGER = keccak256('MANAGER');

    IStaderConfig public staderConfig;
    uint256 public numLots;

    uint256[] public startBlock;
    uint256[] public endBlock;
    uint256[] public sdAmount;
    uint256[] public bidIncrement;
    bool[] public cancelled;
    address[] public highestBidder;
    mapping(uint256 => mapping(address => uint256)) public fundsByBidder; // lotId => (bidder => funds)

    // TODO: Manoj move events to interface
    error InSufficientETH();
    error ETHWithdrawFailed();
    error AuctionNotStarted();
    error AuctionEnded();
    error AuctionCancelled();
    error AuctionNotEnded();

    event LotCreated(uint256 lotId, uint256 sdAmount, uint256 startBlock, uint256 endBlock, uint256 bidIncrement);
    event BidPlaced(uint256 lotId, address indexed bidder, uint256 bid);
    event BidWithdrawn(uint256 lotId, address indexed withdrawalAccount, uint256 amount);
    event BidCancelled(uint256 lotId);
    event SDClaimed(uint256 lotId, address indexed highestBidder, uint256 sdAmount);
    event ETHClaimed(uint256 lotId, address indexed sspm, uint256 ethAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig, address _manager) external initializer {
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_manager);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
        _grantRole(MANAGER, _manager);
    }

    function createLot(
        uint256 _sdAmount,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _bidIncrement
    ) external whenNotPaused onlyRole(MANAGER) {
        require(_startBlock >= block.number, 'past startBlock');
        require(_startBlock < _endBlock, 'startBlock gt eq to endBlock');

        sdAmount.push(_sdAmount);
        bidIncrement.push(_bidIncrement);
        startBlock.push(_startBlock);
        endBlock.push(_endBlock);
        numLots++;

        emit LotCreated(numLots - 1, _sdAmount, _startBlock, _endBlock, _bidIncrement);
    }

    function getHighestBid(uint256 lotId) public view returns (uint256) {
        return fundsByBidder[lotId][highestBidder[lotId]];
    }

    function placeBid(uint256 lotId)
        external
        payable
        onlyAfterStart(lotId)
        onlyBeforeEnd(lotId)
        onlyNotCancelled(lotId)
        whenNotPaused
    {
        // reject payments of 0 ETH
        if (msg.value == 0) revert InSufficientETH();

        uint256 newBid = fundsByBidder[lotId][msg.sender] + msg.value;
        uint256 _highestBid = getHighestBid(lotId);
        if (newBid <= _highestBid) revert InSufficientETH();

        fundsByBidder[lotId][msg.sender] = newBid;
        highestBidder[lotId] = msg.sender;

        emit BidPlaced(lotId, msg.sender, newBid);
    }

    function cancelAuction(uint256 lotId) external onlyBeforeEnd(lotId) onlyNotCancelled(lotId) onlyRole(MANAGER) {
        cancelled[lotId] = true;
        emit BidCancelled(lotId);
    }

    function claimSD(uint256 lotId) external onlyEnded(lotId) {
        uint256 _sdAmount = sdAmount[lotId];
        require(_sdAmount > 0, 'Already Claimed');
        sdAmount[lotId] = 0;

        IERC20(staderConfig.getStaderToken()).transfer(highestBidder[lotId], _sdAmount);
        emit SDClaimed(lotId, highestBidder[lotId], sdAmount[lotId]);
    }

    function claimETH(uint256 lotId) external onlyEnded(lotId) {
        uint256 _ethAmount = getHighestBid(lotId);
        require(_ethAmount > 0, 'Already Claimed');
        fundsByBidder[lotId][highestBidder[lotId]] = 0;

        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveEthFromAuction{value: _ethAmount}();
        emit ETHClaimed(lotId, staderConfig.getStakePoolManager(), _ethAmount);
    }

    function claim(uint256 lotId) external onlyEndedOrCancelled(lotId) {
        address withdrawalAccount = msg.sender;
        uint256 withdrawalAmount = fundsByBidder[lotId][withdrawalAccount];

        if (withdrawalAmount == 0) revert InSufficientETH();

        fundsByBidder[lotId][withdrawalAccount] -= withdrawalAmount;

        // send the funds
        (bool success, ) = payable(withdrawalAccount).call{value: withdrawalAmount}('');
        if (!success) revert ETHWithdrawFailed();

        emit BidWithdrawn(lotId, withdrawalAccount, withdrawalAmount);
    }

    // TODO: Manoj move to interface
    modifier onlyAfterStart(uint256 lotId) {
        if (block.number < startBlock[lotId]) revert AuctionNotStarted();
        _;
    }

    modifier onlyBeforeEnd(uint256 lotId) {
        if (block.number > endBlock[lotId]) revert AuctionEnded();
        _;
    }

    modifier onlyNotCancelled(uint256 lotId) {
        if (cancelled[lotId]) revert AuctionCancelled();
        _;
    }

    modifier onlyEnded(uint256 lotId) {
        if (block.number <= endBlock[lotId]) revert AuctionNotEnded();
        _;
    }

    modifier onlyEndedOrCancelled(uint256 lotId) {
        require(block.number > endBlock[lotId] || cancelled[lotId], 'Auction not ended and not cancelled');
        _;
    }
}
