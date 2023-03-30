// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IAuction {
    // errors
    error InSufficientETH();
    error ETHWithdrawFailed();
    error AuctionNotStarted();
    error AuctionEnded();
    error AuctionCancelled();
    error AuctionNotEnded();

    // events
    event LotCreated(uint256 lotId, uint256 sdAmount, uint256 startBlock, uint256 endBlock, uint256 bidIncrement);
    event BidPlaced(uint256 lotId, address indexed bidder, uint256 bid);
    event BidWithdrawn(uint256 lotId, address indexed withdrawalAccount, uint256 amount);
    event BidCancelled(uint256 lotId);
    event SDClaimed(uint256 lotId, address indexed highestBidder, uint256 sdAmount);
    event ETHClaimed(uint256 lotId, address indexed sspm, uint256 ethAmount);

    // methods
    function createLot(
        uint256 _sdAmount,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _bidIncrement
    ) external;

    function getHighestBid(uint256 lotId) external view returns (uint256);

    function placeBid(uint256 lotId) external payable;

    function cancelAuction(uint256 lotId) external;

    function claimSD(uint256 lotId) external;

    function claimETH(uint256 lotId) external;

    function withdraw(uint256 lotId) external;
}
