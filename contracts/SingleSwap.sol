// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import './interfaces/SDCollateral/ISwapRouter.sol';

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract SingleSwap {
    ISwapRouter public swapRouter;

    uint24 public poolFee;
    uint160 public sqrtPriceLimitX96;
    address public immutable WETH9;
    address public admin;

    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, 'Accessible only by StakeManager Contract');
        _;
    }

    constructor(
        address _admin,
        address _router,
        address _weth9
    ) checkZeroAddress(_admin) checkZeroAddress(_router) checkZeroAddress(_weth9) {
        admin = _admin;
        swapRouter = ISwapRouter(_router);
        WETH9 = _weth9;
        poolFee = 3000;
    }

    // msg.sender must approve this contract to spend tokenIn
    function swapExactInputForETH(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external returns (uint256 amountOut) {
        bool success;
        success = IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        require(success, 'failed: token transfer from sender to contract');

        success = IERC20(tokenIn).approve(address(swapRouter), amountIn);
        require(success, 'failed: token approval from contract to router');

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: WETH9,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: sqrtPriceLimitX96 // TODO: Manoj understand and update it to correct value
        });

        amountOut = swapRouter.exactInputSingle(params);
        swapRouter.unwrapWETH9(amountOutMinimum, recipient); // unwraps all weth of this contract and sends to msg.sender
    }

    // SETTERS

    function updatePoolFee(uint24 _poolFee) external onlyAdmin {
        poolFee = _poolFee;
    }

    function updateSqrtPriceLimitX96(uint160 _sqrtPriceLimitX96) external onlyAdmin {
        sqrtPriceLimitX96 = _sqrtPriceLimitX96;
    }

    function updateRouter(address _router) external checkZeroAddress(_router) onlyAdmin {
        swapRouter = ISwapRouter(_router);
    }
}
