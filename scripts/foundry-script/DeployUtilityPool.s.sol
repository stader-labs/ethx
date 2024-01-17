// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import "forge-std/Script.sol";

import { SDUtilityPool} from "contracts/SDUtilityPool.sol";

import { ProxyFactory } from "script/foundry-script/utils/ProxyFactory.sol";

import {IERC20} from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployUtilityPool is Script {
    address public proxyAdminOwner;
    ProxyAdmin public proxyAdmin;

    ProxyFactory public proxyFactory;

    SDUtilityPool public sdUtilityPoolProxy;

    function run() external {
    
        vm.startBroadcast();

        bytes32 salt = keccak256(abi.encodePacked("ETHx-Stader-Labs"));
        proxyFactory = new ProxyFactory();
        proxyAdmin = new ProxyAdmin(); // msg.sender becomes the owner of ProxyAdmin

        proxyAdminOwner = proxyAdmin.owner();

        console.log("ProxyAdmin deployed at: ", address(proxyAdmin));
        console.log("Owner of ProxyAdmin: ", proxyAdminOwner);

        // deploy implementation contracts
        address sdUtilityPoolImpl = address(new SDUtilityPool());

        console.log('impl is ', sdUtilityPoolImpl);
        // deploy proxy contracts and initialize them
        sdUtilityPoolProxy = SDUtilityPool(proxyFactory.create(address(sdUtilityPoolImpl), address(proxyAdmin), salt));

        // init LRTConfig
        console.log('sdUtilityPoolProxy address is ', address(sdUtilityPoolProxy));

        address sdToken;
        address owner ;
        address staderConfig;


        IERC20(sdToken).approve(address(sdUtilityPoolProxy), 1 ether);
        sdUtilityPoolProxy.initialize(owner,staderConfig);

        console.log("sdUtilityPool proxy deployed at: ", address(sdUtilityPoolProxy));

        vm.stopBroadcast();
    }
}
