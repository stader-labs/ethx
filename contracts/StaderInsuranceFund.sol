// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { UtilLib } from "./library/UtilLib.sol";

import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { IPermissionedPool } from "./interfaces/IPermissionedPool.sol";
import { IStaderInsuranceFund } from "./interfaces/IStaderInsuranceFund.sol";

contract StaderInsuranceFund is IStaderInsuranceFund, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    IStaderConfig public staderConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // function to add fund for insurance
    function depositFund() external payable override {
        emit ReceivedInsuranceFund(msg.value);
    }

    // `MANAGER` can withdraw access fund
    function withdrawFund(uint256 _amount) external override nonReentrant {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);
        if (address(this).balance < _amount || _amount == 0) {
            revert InvalidAmountProvided();
        }

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(msg.sender).call{ value: _amount }("");
        if (!success) {
            revert TransferFailed();
        }
        emit FundWithdrawn(_amount);
    }

    /**
     * @notice reimburse 1 ETH per key to SSPM for permissioned NOs doing front running or giving invalid signature
     * @dev only permissioned pool can call
     * @param _amount amount of ETH to transfer to permissioned pool
     */
    function reimburseUserFund(uint256 _amount) external override nonReentrant {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.PERMISSIONED_POOL());
        if (address(this).balance < _amount) {
            revert InSufficientBalance();
        }
        //slither-disable-next-line arbitrary-send-eth
        IPermissionedPool(staderConfig.getPermissionedPool()).receiveInsuranceFund{ value: _amount }();
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
