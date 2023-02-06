// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interfaces/IStorage.sol";
import "./ELContract.sol";

contract ELContractFactory {
    IStorage immutable public storageContract;

    constructor (address _storageContract) {
        storageContract = IStorage(_storageContract);
    }

    // Calculates the predetermined execution layer contract address from given pubkey
    function getProxyAddress(bytes calldata _pubkey) external view returns(address) {
        require(_pubkey.length == 48, "Invalid pubkey length");

        bytes32 pubkey_root = sha256(abi.encodePacked(_pubkey, bytes16(0)));
        return Clones.predictDeterministicAddress(implementation, salt);(pubkey_root, type(ELContract).creationCode);
    }

    // Uses CREATE2 to deploy a execution layer contract at predetermined address
    function createProxy(bytes calldata _pubkey) external {
        Create2.deploy(uint256(0), _pubkey, type(ELContract).creationCode);
    }
}