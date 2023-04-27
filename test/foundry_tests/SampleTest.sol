pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

import '../../contracts/Auction.sol';

contract SampleTest is Test {
    uint256 testNumber;
    Auction auction;

    function setUp() public {
        testNumber = 42;
        ProxyAdmin admin = new ProxyAdmin();
        Auction impl = new Auction();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(admin), '');
        auction = Auction(address(proxy));

        address staderAdmin = 0x7c1b1F632553633Fe8cFE1bF07a4236a2b851cb5;
        address staderConfig = 0x4f99AcE6fea882112DffDF547e9B63F763916cda;

        auction.initialize(staderAdmin, staderConfig);
    }

    function test_NumberIs42() public {
        assertEq(testNumber, 42);
    }

    function test_auctionIsCreated() public {
        uint256 sdAmount = 2e18;
        auction.createLot(sdAmount);
        assertEq(auction.bidIncrement(), 1e16);
    }

    function testFail_Subtract43() public {
        testNumber -= 43;
    }
}
