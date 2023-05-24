pragma solidity 0.8.16;

import '../../contracts/library/UtilLib.sol';

import '../../contracts/StaderConfig.sol';
import '../../contracts/ETHx.sol';

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract ETHxTest is Test {
    address staderAdmin;
    address staderManager;

    StaderConfig staderConfig;
    ETHx ethx;

    function setUp() public {
        staderAdmin = vm.addr(100);
        staderManager = vm.addr(101);
        address ethDepositAddr = vm.addr(102);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        StaderConfig configImpl = new StaderConfig();
        TransparentUpgradeableProxy configProxy = new TransparentUpgradeableProxy(
            address(configImpl),
            address(proxyAdmin),
            ''
        );
        staderConfig = StaderConfig(address(configProxy));
        staderConfig.initialize(staderAdmin, ethDepositAddr);

        ETHx ethxImpl = new ETHx();
        TransparentUpgradeableProxy ethxProxy = new TransparentUpgradeableProxy(
            address(ethxImpl),
            address(proxyAdmin),
            ''
        );
        ethx = ETHx(address(ethxProxy));
        ethx.initialize(staderAdmin, address(staderConfig));

        vm.startPrank(staderAdmin);
        staderConfig.grantRole(staderConfig.MANAGER(), staderManager);
        staderConfig.updateETHxToken(address(ethx));
        vm.stopPrank();
    }

    function test_JustToIncreaseCoverage() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        ETHx ethxImpl = new ETHx();
        TransparentUpgradeableProxy ethxProxy = new TransparentUpgradeableProxy(
            address(ethxImpl),
            address(proxyAdmin),
            ''
        );
        ETHx ethx2 = ETHx(address(ethxProxy));
        ethx2.initialize(staderAdmin, address(staderConfig));
    }

    function test_ethxInitialize() public {
        assertEq(address(ethx.staderConfig()), address(staderConfig));
        assertEq(staderConfig.getETHxToken(), address(ethx));
        UtilLib.onlyManagerRole(staderManager, staderConfig);

        assertTrue(ethx.hasRole(ethx.DEFAULT_ADMIN_ROLE(), staderAdmin));
        assertEq(ethx.totalSupply(), 0);
    }

    function test_mint(
        uint64 randomPrivateKey,
        uint64 randomPrivateKey2,
        uint256 amount
    ) public {
        address minter = vm.addr(1);
        bytes32 MINTER_ROLE = ethx.MINTER_ROLE();

        vm.expectRevert(); // anyone cannot grantRole, only role's admin
        ethx.grantRole(MINTER_ROLE, minter);

        vm.prank(staderAdmin);
        ethx.grantRole(MINTER_ROLE, minter);

        vm.assume(randomPrivateKey > 1); // anyone except minter
        vm.assume(randomPrivateKey2 > 0);
        address randomUser = vm.addr(randomPrivateKey);
        address randomUser2 = vm.addr(randomPrivateKey2);

        vm.prank(randomUser);
        vm.expectRevert();
        ethx.mint(randomUser2, amount);

        assertEq(ethx.balanceOf(randomUser2), 0);
        vm.prank(minter);
        ethx.mint(randomUser2, amount);
        assertEq(ethx.balanceOf(randomUser2), amount);
    }

    function test_mint(
        uint64 randomPrivateKey,
        uint64 randomPrivateKey2,
        uint256 amount,
        uint256 burnAmount
    ) public {
        address minter = vm.addr(1);
        bytes32 MINTER_ROLE = ethx.MINTER_ROLE();

        vm.prank(staderAdmin);
        ethx.grantRole(MINTER_ROLE, minter);

        vm.assume(randomPrivateKey > 1); // anyone except minter
        vm.assume(randomPrivateKey2 > 0);
        address randomUser = vm.addr(randomPrivateKey);
        address randomUser2 = vm.addr(randomPrivateKey2);

        assertEq(ethx.balanceOf(randomUser2), 0);
        vm.prank(minter);
        ethx.mint(randomUser2, amount);
        assertEq(ethx.balanceOf(randomUser2), amount);

        // random user tries to burn ethx from randomUser2
        vm.assume(burnAmount <= amount);

        vm.prank(randomUser);
        vm.expectRevert();
        ethx.burnFrom(randomUser2, burnAmount);

        address burner = vm.addr(2);
        bytes32 BURNER_ROLE = ethx.BURNER_ROLE();
        vm.prank(staderAdmin);
        ethx.grantRole(BURNER_ROLE, burner);

        vm.prank(burner);
        ethx.burnFrom(randomUser2, burnAmount);
        assertEq(ethx.balanceOf(randomUser2), amount - burnAmount);
    }

    function test_pause_unpause(uint8 randomPrivateKey) public {
        address minter = vm.addr(1);
        address burner = vm.addr(2);
        bytes32 MINTER_ROLE = ethx.MINTER_ROLE();
        bytes32 BURNER_ROLE = ethx.BURNER_ROLE();
        vm.startPrank(staderAdmin);
        ethx.grantRole(MINTER_ROLE, minter);
        ethx.grantRole(BURNER_ROLE, burner);
        vm.stopPrank();

        vm.assume(randomPrivateKey > 0 && randomPrivateKey != 101 && randomPrivateKey != 100); // 101 is staderManager, 100 is staderAdmin
        address randomUser = vm.addr(randomPrivateKey);

        // all methods are functional
        vm.prank(minter);
        ethx.mint(randomUser, 2 ether);

        vm.prank(burner);
        ethx.burnFrom(randomUser, 1 ether);

        // random user tries to pause
        vm.prank(randomUser);
        vm.expectRevert();
        ethx.pause();

        // staderAdmin tries to pause
        vm.prank(staderAdmin);
        vm.expectRevert();
        ethx.pause();

        vm.prank(staderManager);
        ethx.pause();

        // after pause methods are not functional

        vm.prank(minter);
        vm.expectRevert();
        ethx.mint(randomUser, 2 ether);

        vm.prank(burner);
        vm.expectRevert();
        ethx.burnFrom(randomUser, 1 ether);

        // Let's unpause
        // only staderAdmin

        vm.prank(randomUser);
        vm.expectRevert();
        ethx.unpause();

        vm.prank(staderAdmin);
        ethx.unpause();

        // all methods are functional again
        vm.prank(minter);
        ethx.mint(randomUser, 2 ether);

        vm.prank(burner);
        ethx.burnFrom(randomUser, 1 ether);
    }

    function test_updateStaderConfig() public {
        assertEq(address(ethx.staderConfig()), address(staderConfig));

        // not staderAdmin
        vm.expectRevert();
        ethx.updateStaderConfig(vm.addr(203));

        vm.prank(staderAdmin);
        ethx.updateStaderConfig(vm.addr(203));
        assertEq(address(ethx.staderConfig()), vm.addr(203));
    }
}
