// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../library/UtilLib.sol';
import '../../interfaces/DVT/SSV/ISSVVaultProxy.sol';

//contract to delegate call to ssv validator withdraw vault implementation
contract SSVVaultProxy is ISSVVaultProxy {
    bool public override vaultSettleStatus;
    bool public override isInitialized;
    uint8 public override poolId;
    uint256 public override validatorId;
    address public override owner;
    IStaderConfig public override staderConfig;

    constructor() {
        isInitialized = true;
    }

    //initialise the vault proxy with data
    function initialise(
        uint8 _poolId,
        uint256 _validatorId,
        address _staderConfig
    ) external {
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        UtilLib.checkNonZeroAddress(_staderConfig);
        isInitialized = true;
        poolId = _poolId;
        validatorId = _validatorId;
        staderConfig = IStaderConfig(_staderConfig);
        owner = staderConfig.getAdmin();
        UtilLib.checkNonZeroAddress(owner);
    }

    /**route all call to this proxy contract to the latest SSV validator withdrawl vault contract
     * fetched from staderConfig. This approach will help in changing the implementation
     * of ssv validator's withdrawal vault for already deployed vaults*/
    fallback(bytes calldata _input) external payable returns (bytes memory) {
        (bool success, bytes memory data) = (staderConfig.getSSVValidatorWithdrawalVault()).delegatecall(_input);
        if (!success) {
            revert(string(data));
        }
        return data;
    }

    /**
     * @notice update the address of stader config contract
     * @dev only owner can call
     * @param _staderConfig address of updated staderConfig
     */
    function updateStaderConfig(address _staderConfig) external override onlyOwner {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    // update the owner of vault proxy contract to staderConfig Admin
    function updateOwner() external override {
        owner = staderConfig.getAdmin();
        emit UpdatedOwner(owner);
    }

    //modifier to check only owner
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CallerNotOwner();
        }
        _;
    }
}
