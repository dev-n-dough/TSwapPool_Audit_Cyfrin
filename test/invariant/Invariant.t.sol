// SPDX-License_Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant,Test{
    // these pool has 2 assets
    ERC20Mock poolToken;
    ERC20Mock weth;
    // we will need the contracts
    PoolFactory factory;
    TSwapPool pool; // this is our poolToken/weth pool
    Handler handler;

    int256 constant STARTING_X = 100e18; // poolToken
    int256 constant STARTING_Y = 50e18; // weth

    function setUp() public{
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

        // create those initial X and Y balances
        poolToken.mint(address(this), uint256(STARTING_X));
        weth.mint(address(this), uint256(STARTING_Y));

        // poolToken.approve(address(this),uint256(STARTING_X));
        // weth.approve(address(this),uint256(STARTING_Y));


        // approve the pool to transfer these tokens
        poolToken.approve(address(pool),type(uint256).max);
        weth.approve(address(pool),type(uint256).max);


        // deposit into the pool
        pool.deposit(
            uint256(STARTING_Y),
            uint256(STARTING_Y), // its the initial 'warm-up' stage , so we can choose whatev we want
            uint256(STARTING_X),
            uint64(block.timestamp)
        );        


        // create the handler
        handler = new Handler(pool);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.swapPoolTokenForWethBasedOnOutputWeth.selector;
        targetSelector(
            FuzzSelector({addr: address(handler) , selectors: selectors})
        );
        targetContract(address(handler));
    }

    function statefulFuzz_constantProductFormulaStaysTheSameX() public view
    {
        assertEq(handler.actualDeltaX() , handler.expectedDeltaX());
    }

    function statefulFuzz_constantProductFormulaStaysTheSameY() public view
    {
        assertEq(handler.actualDeltaY() , handler.expectedDeltaY());
    }
}