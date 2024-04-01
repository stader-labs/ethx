// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';

/// @title ProxyFactory Contract
/// @notice The contract that handles the creation of proxies for the LRT contracts
contract ProxyFactory {
    /// @dev Creates a proxy for the given implementation
    /// @param implementation the implementation to proxy
    /// @param proxyAdmin the proxy admin to use
    /// @param salt the salt to use for the proxy
    /// @return the address of the created proxy
    function create(
        address implementation,
        address proxyAdmin,
        bytes32 salt
    ) external returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{salt: salt}(implementation, proxyAdmin, '');
        return address(proxy);
    }

    /// @dev Computes the address of a proxy for the given implementation
    /// @param implementation the implementation to proxy
    /// @param proxyAdmin the proxy admin to use
    /// @param salt the salt to use for the proxy
    /// @return the address of the created proxy
    function computeAddress(
        address implementation,
        address proxyAdmin,
        bytes32 salt
    ) external view returns (address) {
        bytes memory creationCode = type(TransparentUpgradeableProxy).creationCode;
        bytes memory contractBytecode = abi.encodePacked(creationCode, abi.encode(implementation, proxyAdmin, ''));

        return Create2.computeAddress(salt, keccak256(contractBytecode));
    }
}
