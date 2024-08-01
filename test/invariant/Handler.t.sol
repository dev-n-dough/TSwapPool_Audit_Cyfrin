// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test,console2} from "forge-std/Test.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test{
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address lp = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // ghost variables
    int256 public startingX; // pool token
    int256 public startingY; // weth
    int256 public expectedDeltaX;
    int256 public expectedDeltaY;
    int256 public actualDeltaX;
    int256 public actualDeltaY;

    constructor(TSwapPool _pool)
    {
        pool = _pool;
        poolToken = ERC20Mock(pool.getPoolToken());
        weth = ERC20Mock(pool.getWeth());
    }

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWeth) public
    {
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        outputWeth = bound(outputWeth,minWeth,type(uint64).max);
        if(outputWeth >= weth.balanceOf(address(pool))){
            return;
        }
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
            );
        if(poolTokenAmount > type(uint64).max)
        {
            return;
        }
        startingX = int256(poolToken.balanceOf(address(pool)));
        startingY = int256(weth.balanceOf(address(pool)));

        expectedDeltaY = int256(-1)* int256(outputWeth);
        expectedDeltaX = int256(poolTokenAmount);

        if(poolToken.balanceOf(swapper) < poolTokenAmount)
        {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        vm.startPrank(swapper);
        poolToken.approve(address(pool),type(uint256).max);
        pool.swapExactOutput(
            poolToken,
            weth,
            outputWeth,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        // check actual delta
        uint256 endingX = poolToken.balanceOf(address(pool));
        uint256 endingY = weth.balanceOf(address(pool));

        actualDeltaX = int256(endingX) - int256(startingX);
        actualDeltaY = int256(endingY) - int256(startingY);

    }

    function deposit(uint256 wethAmount) public{
        // lets make sure it is a reasonable amount to prevent overflow errors
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        wethAmount = bound(wethAmount,minWeth,type(uint64).max);

        startingX = int256(poolToken.balanceOf(address(pool)));
        startingY = int256(weth.balanceOf(address(pool)));

        // i am depositing both so both deltas are positive
        expectedDeltaY = int256(wethAmount);
        expectedDeltaX = int256(pool.getPoolTokensToDepositBasedOnWeth(wethAmount));

        // deposit
        vm.startPrank(lp);
        weth.mint(lp,wethAmount);
        poolToken.mint(lp,uint256(expectedDeltaX));
        weth.approve(address(pool),type(uint256).max);
        poolToken.approve(address(pool),type(uint256).max);

        pool.deposit(
            wethAmount,
            0,
            uint256(expectedDeltaX),
            uint64(block.timestamp)
        );
        vm.stopPrank();

        // check actual delta
        uint256 endingX = poolToken.balanceOf(address(pool));
        uint256 endingY = weth.balanceOf(address(pool));

        actualDeltaX = int256(endingX) - int256(startingX);
        actualDeltaY = int256(endingY) - int256(startingY);
    }
}