// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import 'forge-std/Script.sol';

import {SDUtilityPool} from 'contracts/SDUtilityPool.sol';

import {SDIncentiveController} from 'contracts/SDIncentiveController.sol';

import {ProxyFactory} from 'scripts/foundry-script/utils/ProxyFactory.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ProxyAdmin} from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract DeployUtilityPool is Script {
    address public proxyAdminOwner;
    ProxyAdmin public proxyAdmin;

    ProxyFactory public proxyFactory;

    SDUtilityPool public sdUtilityPoolProxy;

    SDIncentiveController public sdIncentiveControllerProxy;

    function run() external {
        vm.startBroadcast();

        bytes32 salt = keccak256(abi.encodePacked('ETHx-Stader-Labs'));
        proxyFactory = new ProxyFactory();
        proxyAdmin = new ProxyAdmin(); // msg.sender becomes the owner of ProxyAdmin

        proxyAdminOwner = proxyAdmin.owner();

        console.log('ProxyAdmin deployed at: ', address(proxyAdmin));
        console.log('Owner of ProxyAdmin: ', proxyAdminOwner);

        // deploy implementation contracts
        address sdUtilityPoolImpl = address(new SDUtilityPool());

        address sdIncentiveControllerImpl = address(new SDIncentiveController());

        console.log('impl of UtilityPool is ', sdUtilityPoolImpl);
        console.log('impl of IncentiveController is ', sdIncentiveControllerImpl);

        // deploy proxy contracts and initialize them
        sdUtilityPoolProxy = SDUtilityPool(proxyFactory.create(address(sdUtilityPoolImpl), address(proxyAdmin), salt));

        sdIncentiveControllerProxy = SDIncentiveController(
            proxyFactory.create(sdIncentiveControllerImpl, address(proxyAdmin), salt)
        );

        console.log('sdUtilityPoolProxy address is ', address(sdUtilityPoolProxy));

        console.log('sdIncentive controller address is ', address(sdIncentiveControllerProxy));

        address sdToken; //assign value here;
        address owner; //assign value here;
        address staderConfig; //assign value here;

        IERC20(sdToken).approve(address(sdUtilityPoolProxy), 1 ether);
        sdUtilityPoolProxy.initialize(owner, staderConfig);

        sdIncentiveControllerProxy.initialize(owner, staderConfig);

        console.log('sdUtilityPool proxy deployed at: ', address(sdUtilityPoolProxy));

        console.log('sdIncentiveController proxy deployed at: ', address(sdIncentiveControllerProxy));

        vm.stopBroadcast();
    }
}
