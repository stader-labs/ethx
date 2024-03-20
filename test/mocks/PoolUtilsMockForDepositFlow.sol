// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../../contracts/StaderConfig.sol";

contract PoolUtilsMockForDepositFlow {
    address nodeRegistry;
    address staderConfig;

    error EmptyNameString();
    error NameCrossedMaxLength();
    error InvalidLengthOfPubkey();
    error InvalidLengthOfSignature();
    error PubkeyAlreadyExist();

    uint64 private constant PUBKEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;

    constructor(address _nodeRegistry, address _staderConfig) {
        nodeRegistry = _nodeRegistry;
        staderConfig = _staderConfig;
    }

    function getNodeRegistry(uint8) public view returns (address) {
        return nodeRegistry;
    }

    function getCollateralETH(uint8 poolID) public pure returns (uint256) {
        if (poolID == 1) {
            return 4 ether;
        }
        return 0;
    }

    function isExistingPubkey(bytes calldata) public pure returns (bool) {
        return false;
    }

    function isExistingOperator(address) external pure returns (bool) {
        return false;
    }

    function isExistingPoolId(uint8) external pure returns (bool) {
        return true;
    }

    function getTotalActiveValidatorCount() external pure returns (uint256) {
        return 84;
    }

    function getQueuedValidatorCountByPool(uint8) external pure returns (uint256) {
        return type(uint256).max;
    }

    function getActiveValidatorCountByPool(uint8) external pure returns (uint256) {
        return 15;
    }

    function getPoolIdArray() external pure returns (uint8[] memory) {
        uint8[] memory out = new uint8[](2);
        out[0] = 1;
        out[1] = 2;
        return out;
    }

    function poolAddressById(uint8 poolID) external view returns (address) {
        if (poolID == 1) {
            return StaderConfig(staderConfig).getPermissionlessPool();
        }
        return StaderConfig(staderConfig).getPermissionedPool();
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

    function calculateRewardShare(uint8, uint256) external pure returns (uint256, uint256, uint256) {
        return (0.9 ether, 0.05 ether, 0.05 ether);
    }
}
