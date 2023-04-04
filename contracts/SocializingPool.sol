// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';

import './interfaces/IStaderConfig.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract SocializingPool is
    ISocializingPool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IStaderConfig public staderConfig;
    uint256 public override totalELRewardsCollected;
    uint256 public override totalOperatorETHRewardsRemaining;
    uint256 public override totalOperatorSDRewardsRemaining;
    uint256 public initialBlock;

    bytes32 public constant STADER_ORACLE = keccak256('STADER_ORACLE');

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;
    mapping(uint256 => bool) public handledRewards;

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        initialBlock = block.number;

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function getRewardDetails()
        external
        view
        returns (
            uint256 currentIndex,
            uint256 currentStartBlock,
            uint256 currentEndBlock,
            uint256 nextIndex,
            uint256 nextStartBlock,
            uint256 nextEndBlock
        )
    {
        uint256 cycleDuration = staderConfig.getSocializingPoolCycleDuration();
        currentIndex = IStaderOracle(staderConfig.getStaderOracle()).getCurrentRewardsIndex();
        currentStartBlock = initialBlock + ((currentIndex - 1) * cycleDuration);
        currentEndBlock = currentStartBlock + cycleDuration - 1;
        nextIndex = currentIndex + 1;
        nextStartBlock = currentEndBlock + 1;
        nextEndBlock = nextStartBlock + cycleDuration - 1;
    }

    function handleRewards(RewardsData calldata _rewardsData) external override nonReentrant onlyRole(STADER_ORACLE) {
        require(!handledRewards[_rewardsData.index], 'Rewards already handled for this cycle');
        require(
            _rewardsData.operatorETHRewards + _rewardsData.userETHRewards + _rewardsData.protocolETHRewards <=
                address(this).balance - totalOperatorETHRewardsRemaining,
            'insufficient eth rewards'
        );
        require(
            _rewardsData.operatorSDRewards <=
                IERC20(staderConfig.getStaderToken()).balanceOf(address(this)) - totalOperatorSDRewardsRemaining,
            'insufficient sd rewards'
        );

        handledRewards[_rewardsData.index] = true;
        totalOperatorETHRewardsRemaining += _rewardsData.operatorETHRewards;
        totalOperatorSDRewardsRemaining += _rewardsData.operatorSDRewards;

        bool success;
        (success, ) = payable(staderConfig.getStakePoolManager()).call{value: _rewardsData.userETHRewards}('');
        require(success, 'User ETH rewards transfer failed');

        (success, ) = payable(staderConfig.getStaderTreasury()).call{value: _rewardsData.protocolETHRewards}('');
        require(success, 'Protocol ETH rewards transfer failed');
    }

    // TODO: fetch _operatorRewardAddr from operatorID, once sanjay merges the impl
    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        address _operatorRewardsAddr
    ) external override nonReentrant whenNotPaused {
        (uint256 totalAmountSD, uint256 totalAmountETH) = _claim(
            _index,
            msg.sender,
            _amountSD,
            _amountETH,
            _merkleProof
        );

        bool success;
        if (totalAmountETH > 0) {
            totalOperatorETHRewardsRemaining -= totalAmountETH;
            (success, ) = payable(_operatorRewardsAddr).call{value: totalAmountETH}('');
            require(success, 'Operator ETH rewards transfer failed');
        }

        if (totalAmountSD > 0) {
            totalOperatorSDRewardsRemaining -= totalAmountSD;
            // TODO: cannot use safeTransfer as safeERC20 uses a library named Address and which conflicts with our library 'Address'
            // we should rename our library 'Address'
            success = IERC20(staderConfig.getStaderToken()).transfer(_operatorRewardsAddr, totalAmountSD);
            require(success, 'Protocol ETH rewards transfer failed');
        }
    }

    function _claim(
        uint256[] calldata _index,
        address _operator,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) internal returns (uint256 _totalAmountSD, uint256 _totalAmountETH) {
        for (uint256 i = 0; i < _index.length; i++) {
            require(_amountSD[i] > 0 || _amountETH[i] > 0, 'Invalid amount');
            require(!claimedRewards[_operator][_index[i]], 'Already claimed');

            _totalAmountSD += _amountSD[i];
            _totalAmountETH += _amountETH[i];
            claimedRewards[_operator][_index[i]] = true;

            require(_verifyProof(_index[i], _operator, _amountSD[i], _amountETH[i], _merkleProof[i]), 'Invalid proof');
        }
    }

    function _verifyProof(
        uint256 _index,
        address _operator,
        uint256 _amountSD,
        uint256 _amountETH,
        bytes32[] calldata _merkleProof
    ) internal view returns (bool) {
        bytes32 merkleRoot = IStaderOracle(staderConfig.getStaderOracle()).socializingRewardsMerkleRoot(_index);
        bytes32 node = keccak256(abi.encodePacked(_operator, _amountSD, _amountETH));
        return MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node);
    }
}
