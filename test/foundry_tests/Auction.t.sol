pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/Auction.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';
import '../mocks/StakePoolManagerMock.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract AuctionTest is Test {
    address staderAdmin;
    address staderManager;

    Auction auction;
    StaderConfig staderConfig;
    StaderTokenMock staderToken;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

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
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        vm.stopPrank();

        Auction auctionImpl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(auctionImpl), address(admin), '');
        auction = Auction(address(proxy));
        auction.initialize(staderAdmin, address(staderConfig));
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin admin = new ProxyAdmin();
        Auction auctionImpl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(auctionImpl), address(admin), '');
        Auction auction2 = Auction(address(proxy));
        auction2.initialize(staderAdmin, address(staderConfig));
    }

    function test_auctionInitialize() public {
        assertEq(address(auction.staderConfig()), address(staderConfig));
        assertEq(auction.duration(), 2 * auction.MIN_AUCTION_DURATION());
        assertEq(auction.bidIncrement(), 5e15);
        assertEq(auction.nextLot(), 1);
        assertTrue(auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), staderAdmin));
        UtilLib.onlyManagerRole(staderManager, staderConfig);
    }

    function testFail_insufficientSDAuctionCreate(uint256 sdAmount) public {
        uint256 userSDBalanceBefore = staderToken.balanceOf(address(this));

        vm.assume(sdAmount > userSDBalanceBefore);
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);
    }

    function test_createLot(uint256 sdAmount) public {
        uint256 userSDBalanceBefore = staderToken.balanceOf(address(this));

        vm.assume(sdAmount <= userSDBalanceBefore);

        assertEq(auction.nextLot(), 1);

        staderToken.approve(address(auction), sdAmount);
        vm.expectCall(
            address(staderToken),
            abi.encodeCall(staderToken.transferFrom, (address(this), address(auction), sdAmount))
        );
        auction.createLot(sdAmount);

        assertEq(staderToken.balanceOf(address(this)), userSDBalanceBefore - sdAmount);

        assertEq(auction.nextLot(), 2);
        (uint256 _startBlock, uint256 _endBlock, uint256 _sdAmount, , , bool sdClaimed, bool ethExtracted) = auction
            .lots(1);
        assertEq(_startBlock, block.number);
        assertEq(_endBlock, block.number + auction.duration());
        assertEq(_sdAmount, sdAmount);
        assertEq(staderToken.balanceOf(address(auction)), sdAmount);
        assertFalse(sdClaimed);
        assertFalse(ethExtracted);
    }

    function test_addBid(
        uint256 sdAmount,
        uint256 u1_bid1,
        uint256 u1_bid2
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
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

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

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

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

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

    function testFail_addBidAfterAuctionEnds(
        uint256 sdAmount,
        uint64 extraDuration,
        uint128 u1_bid1
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);

        vm.roll(block.number + auction.duration() + 1 + extraDuration); // sets block.number to
        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);
    }

    function test_revertMethodsBeforeAuctionEnds(
        uint256 sdAmount,
        uint64 duration,
        uint128 u1_bid1
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        vm.assume(duration <= auction.duration()); // any time before auction ends
        vm.roll(block.number + duration); // sets block.number to

        address user1 = vm.addr(1);

        vm.prank(user1);
        vm.expectRevert();
        auction.claimSD(1);

        vm.expectRevert();
        auction.transferHighestBidToSSPM(1);

        vm.expectRevert();
        auction.extractNonBidSD(1);

        vm.expectRevert();
        auction.withdrawUnselectedBid(1);

        // user bids
        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);

        vm.prank(user1);
        vm.expectRevert();
        auction.claimSD(1);

        vm.expectRevert();
        auction.transferHighestBidToSSPM(1);

        vm.expectRevert();
        auction.extractNonBidSD(1);

        vm.expectRevert();
        auction.withdrawUnselectedBid(1);
    }

    function test_UserClaimsSD(
        uint256 sdAmount,
        uint64 extraDuration,
        uint128 u1_bid1,
        uint8 randUserSeed
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);

        // Auction Ends
        vm.roll(block.number + auction.duration() + 1 + extraDuration); // sets block.number to

        // reverts if claimed by non-highest bidder
        vm.assume(randUserSeed > 1);
        address user2 = vm.addr(randUserSeed);
        vm.prank(user2);
        vm.expectRevert();
        auction.claimSD(1);

        // highest bidder user1 claims SD
        uint256 u1_sdBalanceBefore = staderToken.balanceOf(user1);
        (, , , , , bool sdClaimed, ) = auction.lots(1);
        assertFalse(sdClaimed);

        vm.prank(user1);
        auction.claimSD(1);
        assertEq(staderToken.balanceOf(user1), u1_sdBalanceBefore + sdAmount);
        (, , , , , bool sdClaimedAfter, ) = auction.lots(1);
        assertTrue(sdClaimedAfter);

        // user1 tries to claim again
        vm.prank(user1);
        vm.expectRevert();
        auction.claimSD(1);
    }

    function test_transferHighestBidToSSPM_RevertsWhenNoBidPlaced(uint16 duration) public {
        uint256 sdAmount = 5 ether;
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        // set to any random block after auction start block
        vm.roll(block.number + duration);

        vm.expectRevert();
        auction.transferHighestBidToSSPM(1);
    }

    function test_transferHighestBidToSSPM(uint16 extraDuration) public {
        uint256 sdAmount = 5 ether;
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
        hoax(user1, 1 ether);
        auction.addBid{value: 1 ether}(1);

        // set to a block after auction ends
        vm.roll(block.number + auction.duration() + 1 + extraDuration);

        StakePoolManagerMock sspm = new StakePoolManagerMock();
        vm.prank(staderAdmin);
        staderConfig.updateStakePoolManager(address(sspm));

        uint256 sspmEthBalanceBefore = address(sspm).balance;
        auction.transferHighestBidToSSPM(1);

        (, , , , uint256 highestBidAmount, , bool ethExtracted) = auction.lots(1);
        assertEq(address(sspm).balance, sspmEthBalanceBefore + highestBidAmount);
        assertTrue(ethExtracted);

        // reverts if try executing again
        vm.expectRevert();
        auction.transferHighestBidToSSPM(1);
    }

    function test_revert_extractNonBidSD_whenBidPlaced(
        uint256 sdAmount,
        uint256 bid,
        uint64 duration
    ) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance);
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);

        vm.assume(bid > auction.bidIncrement());
        hoax(user1, bid);
        auction.addBid{value: bid}(1);

        vm.roll(block.number + auction.duration() + 1 + duration);

        // LotWasAuctioned()
        vm.expectRevert();
        auction.extractNonBidSD(1);
    }

    function test_extractNonBidSD(uint256 sdAmount, uint64 duration) public {
        uint256 deployerSDBalance = staderToken.balanceOf(address(this));
        vm.assume(sdAmount <= deployerSDBalance && sdAmount > 0);
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        vm.roll(block.number + auction.duration() + 1 + duration);

        address treasury = vm.addr(3);
        vm.prank(staderManager);
        staderConfig.updateStaderTreasury(treasury);

        uint256 treasurySDBalanceBefore = staderToken.balanceOf(treasury);
        auction.extractNonBidSD(1);
        assertEq(staderToken.balanceOf(treasury), treasurySDBalanceBefore + sdAmount);

        // AlreadyClaimed()
        vm.expectRevert();
        auction.extractNonBidSD(1);
    }

    function test_withdrawUnselectedBid(
        uint64 duration,
        uint128 u1_bid1,
        uint128 u2_bid1
    ) public {
        uint256 sdAmount = 3 ether;
        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        vm.assume(u1_bid1 > auction.bidIncrement());
        hoax(user1, u1_bid1);
        auction.addBid{value: u1_bid1}(1);
        (, , , , uint256 highestBidAmount, , ) = auction.lots(1);

        vm.assume(u2_bid1 >= highestBidAmount + auction.bidIncrement());
        hoax(user2, u2_bid1);
        auction.addBid{value: u2_bid1}(1);

        // Auction ends
        vm.roll(block.number + auction.duration() + 1 + duration);

        // user2 withdrawUnselectedBid : reverts as user2 is highest bidder
        vm.prank(user2);
        vm.expectRevert();
        auction.withdrawUnselectedBid(1);

        uint256 user1_ethBalance = address(user1).balance;
        vm.prank(user1);
        auction.withdrawUnselectedBid(1);
        assertEq(address(user1).balance, user1_ethBalance + u1_bid1);

        // fails if user1 tries to withdrawUnselectedBid again
        vm.prank(user1);
        vm.expectRevert();
        auction.withdrawUnselectedBid(1);
    }

    function test_updateStaderConfig() public {
        vm.prank(staderAdmin);
        auction.updateStaderConfig(vm.addr(203));
        assertEq(address(auction.staderConfig()), vm.addr(203));
    }

    function test_updateDuration(uint256 newDuration) public {
        vm.assume(newDuration >= auction.MIN_AUCTION_DURATION());
        vm.prank(staderManager);
        auction.updateDuration(newDuration);
        assertEq(auction.duration(), newDuration);
    }

    function testFail_shortUpdateDuration(uint256 newDuration) public {
        vm.assume(newDuration < auction.MIN_AUCTION_DURATION());
        vm.prank(staderManager);
        auction.updateDuration(newDuration);
    }

    function test_updateBidIncrement(uint256 newBidIncrement) public {
        vm.prank(staderManager);
        auction.updateBidIncrement(newBidIncrement);
        assertEq(auction.bidIncrement(), newBidIncrement);
    }
}
