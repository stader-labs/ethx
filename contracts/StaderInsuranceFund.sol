// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/IPermissionedPool.sol';
import './interfaces/IStaderInsuranceFund.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderInsuranceFund is IStaderInsuranceFund, Initializable, AccessControlUpgradeable {
    IStaderConfig public staderConfig;
    bytes32 public constant STADER_MANAGER = keccak256('STADER_MANAGER');
    bytes32 public constant PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        __AccessControl_init_unchained();
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    // function to add fund for insurance
    function depositFund() external payable override {
        emit ReceivedInsuranceFund(msg.value);
    }

    // `STADER_MANAGER` can withdraw access fund
    function withdrawFund(uint256 _amount) external override onlyRole(STADER_MANAGER) {
        if (address(this).balance < _amount || _amount == 0) {
            revert InvalidAmountProvided();
        }

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(msg.sender).call{value: _amount}('');
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
    function reimburseUserFund(uint256 _amount) external override onlyRole(PERMISSIONED_POOL) {
        if (address(this).balance < _amount) {
            revert InSufficientBalance();
        }
        IPermissionedPool(staderConfig.getPermissionedPool()).receiveInsuranceFund{value: _amount}();
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
