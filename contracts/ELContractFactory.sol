// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/proxy/Clones.sol';

import './interfaces/IStorage.sol';
import './ELContract.sol';

contract ELContractFactory {
    address public implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), 'Zero address');
        implementation = _implementation;
    }

    function getPubkeyRoot(bytes calldata _pubkey) public pure returns (bytes32) {
        require(_pubkey.length == 48, 'Invalid pubkey length');

        return sha256(abi.encodePacked(_pubkey, bytes16(0)));
    }

    // Calculates the predetermined execution layer clone contract address from given pubkey
    function getProxyAddress(bytes calldata _pubkey) external view returns (address) {
        bytes32 pubkeyRoot = getPubkeyRoot(_pubkey);
        return Clones.predictDeterministicAddress(implementation, pubkeyRoot);
    }

    // Uses CREATE2 to deploy a execution layer clone contract at predetermined address
    function createProxy(bytes calldata _pubkey) external {
        bytes32 pubkeyRoot = getPubkeyRoot(_pubkey);
        Clones.cloneDeterministic(implementation, pubkeyRoot);
    }
}
