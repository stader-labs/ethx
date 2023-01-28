pragma solidity ^8.16.0;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderNodeWithdrawManager is Initializable, AccessControlUpgradeable{

    address public poolManager;

    uint256 public  lockedEtherAmount ;

    uint256 public  processedRequestCounter;

    uint256 public constant MIN_WITHDRAWAL = 0.1 ether;

    WithdrawInfo[] public withdrawRequest;

    uint256 public  finalizedRequestsCounter ;

    struct WithdrawInfo {
        bool claimed;
        address payable recipient;
        uint256 cumulativeEther;
        uint256 cumulativeShares;
        uint256 requestBlockNumber;
    }

    function initialize() external initializer{
        __AccessControl_init_unchained();
    }


}