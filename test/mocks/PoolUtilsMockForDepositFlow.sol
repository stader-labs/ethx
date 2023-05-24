// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract PoolUtilsMockForDepositFlow {
    address nodeRegistry;

    error EmptyNameString();
    error NameCrossedMaxLength();
    error InvalidLengthOfPubkey();
    error InvalidLengthOfSignature();
    error PubkeyAlreadyExist();

    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    constructor(address _nodeRegistry) {
        nodeRegistry = _nodeRegistry;
    }

    function getOperatorPoolId(address) external pure returns (uint8) {
        return 1;
    }

    function getNodeRegistry(uint8) public view returns (address) {
        return nodeRegistry;
    }

    function getCollateralETH(uint8) public pure returns (uint256) {
        return 4 ether;
    }

    function isExistingPubkey(bytes calldata) public pure returns (bool) {
        return false;
    }

    function isExistingOperator(address) external pure returns (bool) {
        return false;
    }

    function onlyValidName(string calldata _name) external pure {
        if (bytes(_name).length == 0) {
            revert EmptyNameString();
        }
        if (bytes(_name).length > 255) {
            revert NameCrossedMaxLength();
        }
    }

    function onlyValidKeys(
        bytes calldata _pubkey,
        bytes calldata _preDepositSignature,
        bytes calldata _depositSignature
    ) external pure {
        if (_pubkey.length != PUBKEY_LENGTH) {
            revert InvalidLengthOfPubkey();
        }
        if (_preDepositSignature.length != SIGNATURE_LENGTH) {
            revert InvalidLengthOfSignature();
        }
        if (_depositSignature.length != SIGNATURE_LENGTH) {
            revert InvalidLengthOfSignature();
        }
        if (isExistingPubkey(_pubkey)) {
            revert PubkeyAlreadyExist();
        }
    }

    function calculateRewardShare(uint8, uint256)
        external
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (0.9 ether, 0.05 ether, 0.05 ether);
    }
}
