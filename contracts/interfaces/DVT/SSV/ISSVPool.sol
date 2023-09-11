// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ISSVPool {
    // Errors
    error UnsupportedOperation();
    error InvalidCommission();
    error CouldNotDetermineExcessETH();

    // Events
    event ValidatorPreDepositedOnBeaconChain(bytes pubKey);
    event ValidatorDepositedOnBeaconChain(uint256 indexed validatorId, bytes pubKey);
    event UpdatedCommissionFees(uint256 protocolFee, uint256 operatorFee);
    event ReceivedCollateralETH(uint256 amount);
    event UpdatedStaderConfig(address staderConfig);
    event ReceivedInsuranceFund(uint256 amount);
    event TransferredETHToSSPMForDefectiveKeys(uint256 amount);

    // Setters

    function setCommissionFees(uint256 _protocolFee, uint256 _operatorFee) external; // sets the commission fees, protocol and operator

    function receiveInsuranceFund() external payable;

    function transferETHOfDefectiveKeysToSSPM(uint256 _defectiveKeyCount) external;

    function fullDepositOnBeaconChain(bytes[] calldata _pubkey) external;

    //Getters

    function protocolFee() external view returns (uint256); // returns the protocol fee

    function operatorFee() external view returns (uint256); // returns the operator fee

    function stakeUserETHToBeaconChain() external payable;

    function getSocializingPoolAddress() external view returns (address);

    function getNodeRegistry() external view returns (address);
}
