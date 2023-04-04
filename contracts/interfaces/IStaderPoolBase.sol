// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './INodeRegistry.sol';

interface IStaderPoolBase {
    // Errors
    error CommissionFeesMoreThanTOTAL_FEE();
    error ProtocolFeeUnchanged();
    error OperatorFeeUnchanged();
    error UnsupportedOperation();

    // Events
    event ValidatorPreDepositedOnBeaconChain(bytes indexed pubKey);
    event ValidatorDepositedOnBeaconChain(uint256 indexed validatorId, bytes pubKey);
    event UpdatedCommissionFees(uint256 protocolFee, uint256 operatorFee);
    event ReceivedCollateralETH(uint256 amount);
    event UpdatedStaderConfig(address staderConfig);
    event ReceivedInsuranceFund(uint256 amount);
    event TransferredETHToSSPMForDefectiveKeys(uint256 amount);

    // Setters

    function setCommissionFees(uint256 _protocolFee, uint256 _operatorFee) external; // sets the commission fees, protocol and operator

    //Getters

    function protocolFee() external view returns (uint256); // returns the protocol fee

    function operatorFee() external view returns (uint256); // returns the operator fee

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getAllActiveValidators(uint256 _pageNumber, uint256 _pageSize) external view returns (Validator[] memory);

    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (uint256);

    function stakeUserETHToBeaconChain() external payable;

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory);

    /**
    @notice Returns the details of a specific operator.
    @param _pubkey The public key of the validator whose operator details are to be retrieved.
    @return An Operator struct containing the details of the specified operator.
    */
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory);

    function getSocializingPoolAddress() external view returns (address);

    function getCollateralETH() external view returns (uint256);

    function getNodeRegistry() external view returns (address);

    function isExistingPubkey(bytes calldata _pubkey) external view returns (bool);
}
