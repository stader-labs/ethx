pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

import '../../contracts/Auction.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';

contract AuctionTest is Test {
    address staderAdmin;
    Auction auction;
    StaderConfig staderConfig;
    StaderTokenMock staderToken;

    function setUp() public {
        staderAdmin = vm.addr(100);
        address ethDepositAddr = vm.addr(101);

        staderToken = new StaderTokenMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);
        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        vm.stopPrank();

        Auction auctionImpl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(auctionImpl), address(admin), '');
        auction = Auction(address(proxy));
        auction.initialize(staderAdmin, address(staderConfig));
    }

    function test_auctionInitialize() public {
        assertEq(address(auction.staderConfig()), address(staderConfig));
        assertEq(auction.duration(), auction.MIN_AUCTION_DURATION());
        assertEq(auction.bidIncrement(), 1e16);
        assertEq(auction.nextLot(), 1);
        assertTrue(auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), staderAdmin));
    }

    function testFail_insufficientSDAuctionCreate(uint256 sdAmount) public {
        uint256 userSDBalanceBefore = staderToken.balanceOf(address(this));

        vm.assume(sdAmount > userSDBalanceBefore);
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);
    }

    function test_auctionIsCreated(uint256 sdAmount) public {
        uint256 userSDBalanceBefore = staderToken.balanceOf(address(this));

        vm.assume(sdAmount <= userSDBalanceBefore);

        assertEq(auction.nextLot(), 1);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        assertEq(staderToken.balanceOf(address(this)), userSDBalanceBefore - sdAmount);

        assertEq(auction.nextLot(), 2);
        (uint256 _startBlock, uint256 _endBlock, uint256 _sdAmount, , , , ) = auction.lots(1);
        assertEq(_startBlock, block.number);
        assertEq(_endBlock, block.number + auction.duration());
        assertEq(_sdAmount, sdAmount);
        assertEq(staderToken.balanceOf(address(auction)), sdAmount);
    }

    function test_addBid(
        uint256 sdAmount,
        uint256 u1_bid1,
        uint256 u1_bid2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        vm.assume(u1_bid1 < auction.bidIncrement());
        hoax(user1, u1_bid1); // sets user1 as next method's caller and sends u1_bid1 eth
        vm.expectRevert();
        auction.addBid{value: u1_bid1}(1);

        vm.assume(u1_bid2 > auction.bidIncrement());
        // vm.assume(u1_bid2 + u1_bid2 < type(uint256).max )
        hoax(user1, u1_bid2);
        auction.addBid{value: u1_bid2}(1);
        (, , , address highestBidder, uint256 highestBidAmount, , ) = auction.lots(1);
        assertEq(highestBidder, user1);
        assertEq(highestBidAmount, u1_bid2);
    }

    // used uint128 else it will overflow
    function test_addBidByAnotherUser(
        uint256 sdAmount,
        uint128 u1_bid1,
        uint256 u2_bid1,
        uint256 u2_bid2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);
        (, , , , uint256 highestBidAmount, , ) = auction.lots(1);

        // used uint128, else [highestBidAmount + auction.bidIncrement()] will overflow
        vm.assume(u2_bid1 < highestBidAmount + auction.bidIncrement());
        hoax(user2, u2_bid1);
        vm.expectRevert();
        auction.addBid{value: u2_bid1}(1);

        vm.assume(u2_bid2 >= highestBidAmount + auction.bidIncrement());
        vm.assume(u2_bid2 < type(uint256).max - auction.bidIncrement()); // TODO: fails without this condition, not sure why
        hoax(user2, u2_bid2);
        auction.addBid{value: u2_bid2}(1);
        (, , , address highestBidder, uint256 highestBidAmount2, , ) = auction.lots(1);
        assertEq(highestBidder, user2);
        assertEq(highestBidAmount2, u2_bid2);
    }

    function test_userIncrementsBid(
        uint128 sdAmount,
        uint128 u1_bid1,
        uint128 u1_bidIncrease,
        uint128 u2_bid1
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);
        (, , , , uint256 highestBidAmount, , ) = auction.lots(1);

        vm.assume(u2_bid1 >= highestBidAmount + auction.bidIncrement());
        hoax(user2, u2_bid1);
        auction.addBid{value: u2_bid1}(1);
        (, , , address highestBidder2, uint256 highestBidAmount2, , ) = auction.lots(1);
        assertEq(highestBidder2, user2);
        assertEq(highestBidAmount2, u2_bid1);

        vm.assume(
            uint256(u1_bid1) + uint256(u1_bidIncrease) >= uint256(highestBidAmount2) + uint256(auction.bidIncrement())
        );
        hoax(user1, u1_bidIncrease);
        auction.addBid{value: u1_bidIncrease}(1);
        (, , , address highestBidder3, uint256 highestBidAmount3, , ) = auction.lots(1);
        assertEq(highestBidder3, user1);
        assertEq(highestBidAmount3, uint256(u1_bid1) + uint256(u1_bidIncrease));
    }
}
