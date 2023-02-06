// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStorage.sol';

contract ELContract {
    bytes32 public immutable elContractDelegateKey;
    IStorage public immutable storageContract;

    constructor(address _storageContract) {
        storageContract = IStorage(_storageContract);

        // Precompute storage key for rocketNodeDistributorDelegate
        elContractDelegateKey = keccak256(abi.encodePacked('contract.address', 'ELContractDelegate'));
    }

    // Allow contract to receive ETH without making a delegated call
    receive() external payable {}

    // Delegates all transactions to the target supplied during creation
    fallback() external payable {
        address _target = storageContract.getAddress(elContractDelegateKey);
        assembly {
            calldatacopy(0x0, 0x0, calldatasize())
            let result := delegatecall(gas(), _target, 0x0, calldatasize(), 0x0, 0)
            returndatacopy(0x0, 0x0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
