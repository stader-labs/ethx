pragma solidity ^0.8.16;

abstract contract StaderBasePool {
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    function _validateKeys(
        bytes calldata pubkey,
        bytes memory withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) public pure {
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        bytes32 node = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkey_root, withdrawal_credentials)),
                sha256(abi.encodePacked(DEPOSIT_SIZE, bytes24(0), signature_root))
            )
        );

        // Verify computed and expected deposit data roots match
        require(
            node == deposit_data_root,
            'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
        );
    }
}
