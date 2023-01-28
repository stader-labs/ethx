pragma solidity ^8.16.0;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderWithdrawVault is Initializable, AccessControlUpgradeable{

    uint256 public VALIDATOR_DEPOSIT = 32 ether;
    uint256 public protocolCommission;


    function initialize() external initializer{
        __AccessControl_init_unchained();
    }
    /**
     * @notice Allows the contract to receive ETH
     * @dev skimmed rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }

    function calculateUserShare(uint256 _userDeposit, bool _withdrawStatus) external view{
        if(_withdrawStatus){
            if(address(this).balance > VALIDATOR_DEPOSIT){
                return _userDeposit + ((address(this).balance-VALIDATOR_DEPOSIT)*_userDeposit*(100 - protocolCommission))/(VALIDATOR_DEPOSIT*100)
            }
            else if(address(this).balance < _userDeposit){
                return address(this).balance;
            }
            else(){
                return _userDeposit;
            }
        }
        return (address(this).balance*_userDeposit*(100 - protocolCommission))/(VALIDATOR_DEPOSIT*100);
    }

    function calculateNodeShare(uint256 _nodeDeposit, uint256 _userDeposit, bool _withdrawStatus) external view{
        require(_nodeDeposit+_userDeposit == VALIDATOR_DEPOSIT, 'invalid input');
        if(_withdrawStatus){
            if(address(this).balance > VALIDATOR_DEPOSIT){
                return address(this).balance-calculateUserShare(_userDeposit, _withdrawStatus)-calculateStaderFee(_withdrawStatus);
            }
            else if(address(this).balance <= _userDeposit){
                return 0;
            }
            else(){
                return address(this).balance - _userDeposit;
            }
        }
        return (address(this).balance*_nodeDeposit)/VALIDATOR_DEPOSIT + 
        ((address(this).balance*_userDeposit*protocolCommission)/(VALIDATOR_DEPOSIT*100*2))
    }

    function calculateStaderFee(bool _withdrawStatus) external view{
         if(_withdrawStatus){
            if(address(this).balance >VALIDATOR_DEPOSIT){
                return ((address(this).balance-VALIDATOR_DEPOSIT)*_userDeposit*protocolCommission)/(VALIDATOR_DEPOSIT*100*2)
            }
            else{
                return 0;
            }
         }
        return (address(this).balance*_userDeposit*protocolCommission)/(VALIDATOR_DEPOSIT*100*2);
    }
}