// pragma solidity ^0.8.16;

// import './interfaces/IDepositContract.sol';
// import './interfaces/IStaderValidatorRegistry.sol';
// import './interfaces/IStaderManagedStakePool.sol';

// import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
// import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

// contract StaderManagedStakePool is
//     IStaderManagedStakePool,
//     Initializable,
//     AccessControlUpgradeable,
//     PausableUpgradeable
// {
//     uint256 public constant DEPOSIT_SIZE = 32 ether;
//     IDepositContract public ethValidatorDeposit;
//     IStaderValidatorRegistry public staderValidatorRegistry;

//     bytes32 public constant STADER_POOL_ADMIN_ROLE = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN_ROLE');

//     // Assign the node deposit to the minipool
//     // Only accepts calls from the RocketNodeDeposit contract
//     function nodeDeposit(bytes calldata _validatorPubkey, bytes calldata _validatorSignature, bytes32 _depositDataRoot) override external payable onlyLatestContract("rocketNodeDeposit", msg.sender) onlyInitialised {
//         // Check current status & node deposit status
//         require(status == MinipoolStatus.Initialised, "The node deposit can only be assigned while initialised");
//         require(!nodeDepositAssigned, "The node deposit has already been assigned");
//         // Progress full minipool to prelaunch
//         if (depositType == MinipoolDeposit.Full) { setStatus(MinipoolStatus.Prelaunch); }
//         // Update node deposit details
//         nodeDepositBalance = msg.value;
//         nodeDepositAssigned = true;
//         // Emit ether deposited event
//         emit EtherDeposited(msg.sender, msg.value, block.timestamp);
//         // Perform the pre-stake to lock in withdrawal credentials on beacon chain
//         preStake(_validatorPubkey, _validatorSignature, _depositDataRoot);
//     }

// }