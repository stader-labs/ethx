
# ETHx Integration guide

  

Deployment addresses can be found at:

- Mainnet: [ethX-mainnet-contract](https://staderlabs.gitbook.io/ethereum/smart-contracts#ethx-mainnet-smart-contracts)

- Testnet: [ethX-testnet-contract](https://staderlabs.gitbook.io/ethereum/smart-contracts#ethx-testnet-smart-contracts)

  


Liquid staking is achieved through `StaderStakePoolManager` contract and the yield-bearing ERC-20 token `ETHx` is given to the user.


### 1. Stake ETH

Send ETH and receive liquid staking ETHx token.
 
```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

//function call staderStakePoolManager deposit function, depositing ETH and minting
//`amountInETHx` ETHx, sent to `_receiver` address
uint256 amountInETHx = IStaderStakePoolManager(staderConfig.getStakePoolManager()).deposit{value: _amountInETH}(
	_receiver
);

emit  Deposited(msg.sender, _receiver, _amountInETH, amountInETHx);
```

### 2. Approve ETHx
sets `_amountInETHx` as the allowance of userWithdrawalManager contract over this contract ETHx.

```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

bool success = ETHx(staderConfig.getETHxToken()).approve(staderConfig.getUserWithdrawManager(), _amountInETHx);

require(success, 'Approved Failed');
```

### 3. Unstake ETH 

  

Send ETHx and create a withdrawal request to initiate ETHx redemption.

```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

// get userWithdrawalManager contract from staderConfig
IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

//call stader userWithdrawalManager contract's requestWithdraw function, locking ETHx
// generate a unique requestID, set the owner of unstake request to `_owner`
uint256 requestID = userWithdrawalManager.requestWithdraw(_amountInETHx, _owner);

emit  WithdrawRequestReceived(msg.sender, _owner, requestID, _amountInETHx);
```


### 4. Claim ETH

Once the withdraw request is finalized, ETH can be withdrawn back to wallet. This step marks the end of ETHx redemption.


```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

// get userWithdrawalManager contract from staderConfig
IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

//get the final amount of ETH to transfer during claim for a finalized request
(, , , uint256 ethFinalized, ) = userWithdrawalManager.userWithdrawRequests(_requestId);

//calls stader userWithdrawManager contract to claim and receives ETH
IUserWithdrawalManager(staderConfig.getUserWithdrawManager()).claim(_requestId);

emit  RequestRedeemed(msg.sender, ethFinalized);
```



### Sample Example of Stake, Unstake and Claim

  


```SOLIDITY
pragma  solidity 0.8.16;

import  './ETHx.sol';
import  './interfaces/IStaderConfig.sol';
import  './interfaces/IStaderStakePoolManager.sol';
import  './interfaces/IUserWithdrawalManager.sol';

contract  Example {

	event  Deposited(address  indexed  caller, address  indexed  receiver, uint256  assets, uint256  shares);

	event  WithdrawRequestReceived(address  indexed  msgSender, address  owner, uint256  requestId, uint256  sharesAmount);

	event  RequestRedeemed(address  receiver, uint256  ethTransferred);

	address  private  STADER_CONFIG_ADDRESS = '0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB'; //mainnet address

	/**
	 * @notice function to stake ETH and mint ETHx by interacting with StaderStakePoolManager Contract
	 * @dev contract should have minimum ETH equal to `_amountInETH` to call this function
	 * @param  _amountInETH amount of ETH to stake
	 * @param  _receiver address to receive minted ETHx
	*/
	function  stake(uint256  _amountInETH, address  _receiver) external  payable {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

		//function call staderStakePoolManager deposit function, depositing ETH and minting
		//`amountInETHx` ETHx, sent to `_receiver` address
		uint256 amountInETHx = IStaderStakePoolManager(staderConfig.getStakePoolManager()).deposit{value: _amountInETH}(
			_receiver
		);

		emit  Deposited(msg.sender, _receiver, _amountInETH, amountInETHx);
	}

	/**
	 * @notice Sets `_amountInETHx` as the allowance of userWithdrawalManager contract over this contract ETHx.
	 * @param  _amountInETHx amount of ETHx to set as allowance
	*/
	function  approve(uint256  _amountInETHx) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);
		bool success = ETHx(staderConfig.getETHxToken()).approve(staderConfig.getUserWithdrawManager(), _amountInETHx);
		require(success, 'Approved Failed');
	}

	/**
	 * @notice function to put unstake request by sending ETHx
	 * @dev ensure that the contract has minimum `_amountInETHx` amount of ETHx and
	 * ETHx approval should be given prior to stader userWithdrawManager contract
	 * @param  _amountInETHx amount of ETHx to unstake
	 * @param  _owner address to be set as owner of unstake request, only owner allowed to claim
	*/
	function  unstake(uint256  _amountInETHx, address  _owner) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

		// get userWithdrawalManager contract from staderConfig
		IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

		//call stader userWithdrawalManager contract's requestWithdraw function, locking ETHx
		// generate a unique requestID, set the owner of unstake request to `_owner`
		uint256 requestID = userWithdrawalManager.requestWithdraw(_amountInETHx, _owner);

		emit  WithdrawRequestReceived(msg.sender, _owner, requestID, _amountInETHx);
	}

	/**
	 * @notice claim the ETH for the finalized unstake request
	 * finalized unstake request is the one which is ready to claim
	 * @dev claimed ETH will go to the owner address set while putting unstake request
	 * only owner is allowed to claim the request
	 * @param  _requestId Request ID to claim
	*/
	function  claim(uint256  _requestId) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

		// get userWithdrawalManager contract from staderConfig
		IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

		//get the final amount of ETH to transfer during claim for a finalized request
		(, , , uint256 ethFinalized, ) = userWithdrawalManager.userWithdrawRequests(_requestId);

		//calls stader userWithdrawManager contract to claim and receives ETH
		IUserWithdrawalManager(staderConfig.getUserWithdrawManager()).claim(_requestId);

		emit  RequestRedeemed(msg.sender, ethFinalized);
	}

}
```

  

