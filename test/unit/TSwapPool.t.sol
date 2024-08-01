// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18); // e NICE t-swap-pool is inheriting from ERC20 , so has its functions // pool is ERC20 Liquidity-Token , this statement is asserting that LP has 100 LT's 
        assertEq(weth.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;

        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        assert(weth.balanceOf(user) >= expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18); // e LP(who is still being pranked) is allowing `pool` to ..spend?.. its LTs ..?
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }
    // e READ all tests

    /*//////////////////////////////////////////////////////////////
                                 AUDIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getInputAmountBasedOnOutput_IncorrectlyCalculatesFees() public
    {

        weth.mint(user, 190e18);
        poolToken.mint(user, 190e18); // to make user balance in both tokens = 200

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 120e18);
        pool.swapExactOutput(poolToken, weth, 10e18, uint64(block.timestamp));
        // for 10 weth output 
        // expected(for 0.3% fee) = 11.14 poolTokens as input 
        // actual (for 90.03% fee) = 111.4 poolTokens
        vm.stopPrank();
        // To prove protocol is charging 90.03% fee , we will show that 111.4 poolTokens were deducted from user balance instead of 11.14 poolTokens
        assert(poolToken.balanceOf(user) < 886e17); // a little more than 111.4 poolTokens were deducted hence a little less than 88.6 were left (200 - 111.4)
        // console.log(poolToken.balanceOf(user)); // 88.554552546528474312
        // console.log(poolToken.balanceOf(address(pool))) ; // 211.445447453471525688
        assert(poolToken.balanceOf(address(pool)) > 2114e17); // it will have little more than 100 + 111.4 = 211.4 (with 18 DP)
    }

    function test_swapExactOutput_HugeInputForSmallOutput() public
    {

        weth.mint(liquidityProvider, 800e18); // now lp has 1000 weth
        weth.mint(user, 10030e18); // now user has 10_040 weth

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 1000e18);
        poolToken.approve(address(pool), 10e18);
        pool.deposit(1000e18, 1000e18, 10e18, uint64(block.timestamp));
        vm.stopPrank();

        console.log(weth.balanceOf(user)); // 10040.000000000000000000 weth
        console.log(poolToken.balanceOf(user)); // 10.000000000000000000 poolToken
        console.log(weth.balanceOf(address(pool)));  // 1000.000000000000000000 weth
        console.log(poolToken.balanceOf(address(pool))); // 10.000000000000000000 poolToken

        vm.startPrank(user);
        weth.approve(address(pool), 10031e18);
        pool.swapExactOutput(weth, poolToken, 5e18, uint64(block.timestamp));
        vm.stopPrank();

        console.log(weth.balanceOf(user)); // 9.909729187562688065 weth
        console.log(poolToken.balanceOf(user)); // 15.000000000000000000 poolToken
        console.log(weth.balanceOf(address(pool))); // 11030.090270812437311935 weth
        console.log(poolToken.balanceOf(address(pool))); // 5.000000000000000000 poolToken

        assert(weth.balanceOf(user) < 10e18); // started with 10_040 weth , and just to take out 5 poolTokens , had to pay 10_030 weth, which is HUGE!!
    }

     function testInvariantBroken() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        uint256 outputWeth = 1e17;

        vm.startPrank(user);
        poolToken.approve(address(pool), type(uint256).max);
        poolToken.mint(user, 100e18);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        int256 startingY = int256(weth.balanceOf(address(pool)));
        int256 expectedDeltaY = int256(-1) * int256(outputWeth);

        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        int256 actualDeltaY = int256(endingY) - int256(startingY);
        assertEq(actualDeltaY, expectedDeltaY);
    }
}