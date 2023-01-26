// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderWithdrawalManager { 
    function MIN_WITHDRAWAL() external view returns (uint256);

    function POOL_MANAGER() external view returns (bytes32);

    function calculateFinalizationParams(
        uint256 _lastIdToFinalize,
        uint256 _totalPooledEther,
        uint256 _totalShares
    ) external view returns (uint256 etherToLock, uint256 sharesToBurn);

    function finalizationPrices(uint256)
        external
        view
        returns (
            uint256 totalPooledEther,
            uint256 totalShares,
            uint256 index
        );

    function finalize(
        uint256 _lastIdToFinalize,
        uint256 _etherToLock,
        uint256 _totalPooledEther,
        uint256 _totalShares
    ) external payable;

    function finalizedRequestsCounter() external view returns (uint256);

    function findPriceHint(uint256 _requestId)
        external
        view
        returns (uint256 hint);
    
    function getLatestRequestId() external view returns(uint256 requestId);

    function lockedEtherAmount() external view returns (uint256);

    function processedRequestCounter() external view returns (uint256);

    function redeem(uint256 _requestId) external returns (address recipient);

    function restake(uint256 _amount) external;

    function withdraw(
        address _recipient,
        uint256 _etherAmount,
        uint256 _sharesAmount
    ) external returns (uint256 requestId);

    function withdrawRequest(uint256)
        external
        view
        returns (
            bool claimed,
            address recipient,
            uint256 cumulativeEther,
            uint256 cumulativeShares,
            uint256 requestBlockNumber
        );
}