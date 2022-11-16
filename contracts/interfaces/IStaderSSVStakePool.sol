// File: contracts/interfaces/IStaderSSVStakePool.sol
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.2;

interface IStaderSSVStakePool {
    event Initialized(uint8 version);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ReceivedFromPoolManager(address indexed from, uint256 amout);
    event addedTostaderSSVRegistry(bytes indexed pubKey, uint256 index);
    event depositToDepositContract(bytes indexed pubKey);
    event registeredValidatortoSSVNetwork(bytes indexed pubKey);
    event removedValidatorfromSSVNetwork(bytes indexed pubKey, uint256 index);
    event updatedValidatortoSSVNetwork(bytes indexed pubKey, uint256 index);

    function depositEthToDepositContract(
        bytes memory pubKey,
        bytes memory withdrawal_credentials,
        bytes memory signature,
        bytes32 deposit_data_root
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

    function registerValidatortoSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encyptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external;

    function removeValidatorfromSSVNetwork(bytes memory publicKey) external;

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

    function updateValidatortoSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encyptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external;
}