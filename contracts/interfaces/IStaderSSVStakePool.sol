// File: contracts/interfaces/IStaderSSVStakePool.sol
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2.0;

interface IStaderSSVStakePool {
    event Initialized(uint8 version);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event receivedFromPoolManager(address indexed from, uint256 amount);
    event addedToStaderSSVRegistry(bytes indexed pubKey, uint256 index);
    event depositToDepositContract(bytes indexed pubKey);
    event registeredValidatorToSSVNetwork(bytes indexed pubKey);
    event removedValidatorFromSSVNetwork(bytes indexed pubKey, uint256 index);
    event updatedValidatorToSSVNetwork(bytes indexed pubKey, uint256 index);

    function depositEthToDepositContract(
        bytes memory pubKey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        bytes32 depositDataRoot
    ) external;

    function ethValidatorDeposit() external view returns (address);

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        external
        view
        returns (uint256);

    function initialize(
        address _ssvNetwork,
        address _ssvToken,
        address _ethValidatorDeposit,
        address _staderValidatorRegistry
    ) external;

    function owner() external view returns (address);

    function receiveEthFromPoolManager() external payable;

    function registerValidatorToSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external;

    function removeValidatorFromSSVNetwork(bytes memory publicKey) external;

    function renounceOwnership() external;

    function ssvNetwork() external view returns (address);

    function ssvToken() external view returns (address);

    function staderSSVRegistry(uint256)
        external
        view
        returns (bytes memory pubKey);

    function staderSSVRegistryCount() external view returns (uint256);

    function staderValidatorRegistry() external view returns (address);

    function transferOwnership(address newOwner) external;

    function updateEthDepositAddress(address _ethValidatorDeposit) external;

    function updateSSVNetworkAddress(address _ssvNetwork) external;

    function updateSSVTokenAddress(address _ssvToken) external;

    function updateValidatorToSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external;
}
