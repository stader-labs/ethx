
# ETHx Integration guide

  

Deployment addresses can be found at:

- Mainnet: [ethX-mainnet-contract](https://staderlabs.gitbook.io/ethereum/smart-contracts#ethx-mainnet-smart-contracts)

- Testnet: [ethX-testnet-contract](https://staderlabs.gitbook.io/ethereum/smart-contracts#ethx-testnet-smart-contracts)

  


Stader’s ETHx is an ERC-20 token that represents staked ETH. Following are the different actions a user can take to mint/burn ETHx.


### 1. Stake ETH

Send ETH and receive minted ETHx token.
 
```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

// function call staderStakePoolManager deposit function, depositing ETH and minting
// `amountInETHx` ETHx, sent to `_receiver` address
uint256 amountInETHx = IStaderStakePoolManager(staderConfig.getStakePoolManager()).deposit{value: _amountInETH}(
	_receiver
);

emit  Deposited(msg.sender, _receiver, _amountInETH, amountInETHx);
```

### 2. Approve ETHx

Set `_amountInETHx` as the allowance for userWithdrawalManager as a spender. This can be done at the ETHx ERC20 token contract. Alternatively, a max approval can be performed once, and this step can be skipped after the first time.

```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

bool success = ETHx(staderConfig.getETHxToken()).approve(staderConfig.getUserWithdrawManager(), _amountInETHx);

require(success, 'Approved Failed');
```

### 3. Unstake ETH 

Create a withdrawal request to initiate ETH redemption.

```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

// get userWithdrawalManager contract from staderConfig
IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

// a call to userWithdrawalManager contract's requestWithdraw function generates 
// a unique requestID, and sets the owner of unstake request to `_owner`
uint256 requestID = userWithdrawalManager.requestWithdraw(_amountInETHx, _owner);

emit  WithdrawRequestReceived(msg.sender, _owner, requestID, _amountInETHx);
```


### 4. Claim ETH

Call the claim function to receive the ETH to the receiver address after the withdrawRequest is finalized. This step marks the end of ETH redemption.


```SOLIDITY

IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

// get userWithdrawalManager contract from staderConfig
IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

// pass requestId from Step 3. ethFinalized is the ETH amount redeemable through a claim
(, , , uint256 ethFinalized, ) = userWithdrawalManager.userWithdrawRequests(_requestId);

// call stader userWithdrawManager contract to claim from _owner address in step 3 to receive ETH.IUserWithdrawalManager(staderConfig.getUserWithdrawManager()).claim(_requestId);

emit  RequestRedeemed(msg.sender, ethFinalized);
```



### Sample Example of Stake, Unstake, and Claim

  


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

		// function call staderStakePoolManager deposit function, depositing ETH and minting
		// `amountInETHx` ETHx, sent to `_receiver` address
		uint256 amountInETHx = IStaderStakePoolManager(staderConfig.getStakePoolManager()).deposit{value: _amountInETH}(
			_receiver
		);

		emit  Deposited(msg.sender, _receiver, _amountInETH, amountInETHx);
	}

	/**
	 * @notice set `_amountInETHx` as the allowance for userWithdrawalManager as a spender
	 * @param  _amountInETHx amount of ETHx to set as allowance
	*/
	function  approve(uint256  _amountInETHx) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);
		bool success = ETHx(staderConfig.getETHxToken()).approve(staderConfig.getUserWithdrawManager(), _amountInETHx);
		require(success, 'Approved Failed');
	}

	/**
	 * @notice function to create unstake request by sending ETHx
	 * @dev ensure that the contract has minimum `_amountInETHx` amount of ETHx and
	 * ETHx approval should be given prior to this step
	 * @param  _amountInETHx amount of ETHx to unstake
     * @param _owner address to be set as owner of unstake request, only owner allowed to claim
	*/
	function  unstake(uint256  _amountInETHx, address  _owner) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

		// get userWithdrawalManager contract from staderConfig
		IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

		// a call to userWithdrawalManager contract's requestWithdraw function generates 
		// a unique requestID, and sets the owner of unstake request to `_owner`
		uint256 requestID = userWithdrawalManager.requestWithdraw(_amountInETHx, _owner);

		emit  WithdrawRequestReceived(msg.sender, _owner, requestID, _amountInETHx);
	}

	/**
	 * @notice claim the ETH associated with a finalized unstake request
	 * @dev call the claim function to receive the ETH to the receiver address after the 
	 * withdrawRequest is finalized
	 * @param  _requestId Request ID to claim
	*/
	function  claim(uint256  _requestId) external {
		IStaderConfig staderConfig = IStaderConfig(STADER_CONFIG_ADDRESS);

		// get userWithdrawalManager contract from staderConfig
		IUserWithdrawalManager userWithdrawalManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());

		// ethFinalized is the ETH amount redeemable through a claim
		(, , , uint256 ethFinalized, ) = userWithdrawalManager.userWithdrawRequests(_requestId);

		//calls stader userWithdrawManager contract to claim and receives ETH
		IUserWithdrawalManager(staderConfig.getUserWithdrawManager()).claim(_requestId);

		emit  RequestRedeemed(msg.sender, ethFinalized);
	}

}
```

  

