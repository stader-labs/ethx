// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

contract SocializingPool is
    ISocializingPool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IStaderConfig public staderConfig;
    address public override poolSelector;
    uint256 public override totalELRewardsCollected;
    uint256 public constant CYCLE_DURATION = 28 days;
    uint256 public initialTimestamp;

    bytes32 public constant SOCIALIZE_POOL_OWNER = keccak256('SOCIALIZE_POOL_OWNER');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        initialTimestamp = block.timestamp;

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
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentIndex = IStaderOracle(staderConfig.getStaderOracle()).socializingRewardsIndex();
        uint256 currentStartTime = initialTimestamp + (currentIndex * CYCLE_DURATION);
        uint256 currentEndTime = currentStartTime + CYCLE_DURATION;
        uint256 nextIndex = currentIndex + 1;
        uint256 nextStartTime = currentEndTime + 1;
        uint256 nextEndTime = nextStartTime + CYCLE_DURATION;

        return (currentIndex, currentStartTime, currentEndTime, nextIndex, nextStartTime, nextEndTime);
    }

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        uint8 _poolId
    ) external override nonReentrant whenNotPaused {
        _claim(_index, msg.sender, _amountSD, _amountETH, _merkleProof);
        // Calculate totals
        uint256 totalAmountSD;
        uint256 totalAmountETH;
        for (uint256 i = 0; i < _index.length; i++) {
            totalAmountSD += _amountSD[i];
            totalAmountETH += _amountETH[i];
        }

        bool success;

        // distribute ETH rewards
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(
            totalAmountETH,
            _poolId
        );

        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveExecutionLayerRewards{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderConfig.getTreasury()).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        // slither-disable-next-line arbitrary-send-eth
        if (operatorShare > 0) {
            (success, ) = payable(msg.sender).call{value: operatorShare}('');
            require(success, 'Operator share transfer failed');
        }

        // distribute SD rewards
        (userShare, operatorShare, protocolShare) = _calculateRewardShare(totalAmountSD, _poolId);
        address staderToken = staderConfig.getStaderToken();

        IERC20Upgradeable(staderToken).transfer(staderConfig.getStakePoolManager(), userShare); // TODO: Manoj discuss if this is okay ?
        IERC20Upgradeable(staderToken).transfer(staderConfig.getTreasury(), protocolShare);
        if (operatorShare > 0) {
            IERC20Upgradeable(staderToken).transfer(msg.sender, operatorShare);
        }
    }

    function _claim(
        uint256[] calldata _index,
        address _operator,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) internal {
        for (uint256 i = 0; i < _index.length; i++) {
            require(_amountSD[i] > 0 || _amountETH[i] > 0, 'Invalid amount');
            require(!claimedRewards[_operator][_index[i]], 'Already claimed');

            claimedRewards[_operator][_index[i]] = true;

            require(_verifyProof(_index[i], _operator, _amountSD[i], _amountETH[i], _merkleProof[i]), 'Invalid proof');
        }
    }

    // Verifies that the
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

    function _calculateRewardShare(uint256 _totalRewards, uint8 _poolId)
        internal
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH(_poolId);
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeeBps = getProtocolFeeBps(_poolId);
        uint256 operatorFeeBps = getOperatorFeeBps(_poolId);

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        _protocolShare = (protocolFeeBps * _userShareBeforeCommision) / 10000;

        _operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeeBps * _userShareBeforeCommision) / 10000;

        _userShare = _totalRewards - _protocolShare - _operatorShare;
    }

    function updatePoolSelector(address _poolSelector) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_poolSelector);
        poolSelector = _poolSelector;
        emit UpdatedPoolSelector(_poolSelector);
    }

    function getProtocolFeeBps(uint8 _poolId) internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getProtocolFee(_poolId);
    }

    function getOperatorFeeBps(uint8 _poolId) internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getOperatorFee(_poolId);
    }

    function getCollateralETH(uint8 _poolId) private view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getCollateralETH(_poolId);
    }
}
