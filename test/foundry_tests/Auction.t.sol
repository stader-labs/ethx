pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

import '../../contracts/Auction.sol';
import '../../contracts/StaderConfig.sol';

import '../mocks/StaderTokenMock.sol';

contract AuctionTest is Test {
    uint256 testNumber;
    Auction auction;
    StaderConfig staderConfig;
    StaderTokenMock staderToken;

    function setUp() public {
        testNumber = 42;
        address staderAdmin = 0x7FFCbC0b2c43d6e32A5B40FBdeA99d2d803f4Dd7;

        staderToken = new StaderTokenMock();
        ProxyAdmin admin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(admin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, vm.addr(1));
        vm.startPrank(staderAdmin);
        staderConfig.updateStaderToken(address(staderToken));
        vm.stopPrank();

        Auction auctionImpl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(auctionImpl), address(admin), '');
        auction = Auction(address(proxy));
        auction.initialize(staderAdmin, address(staderConfig));
    }

    function test_NumberIs42() public {
        assertEq(testNumber, 42);
    }

    function test_auctionIsCreated() public {
        uint256 sdAmount = 2e18;

        assertEq(auction.nextLot(), 1);

        staderToken.approve(address(auction), sdAmount);
        auction.createLot(sdAmount);

        assertEq(auction.nextLot(), 2);
    }

    function testFail_Subtract43() public {
        testNumber -= 43;
    }
}
