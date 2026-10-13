// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Loom} from "../src/Loom.sol";

/// @dev Generates sequences among three holders, including self-transfers,
/// allowance replacement/revocation, and finite or unlimited delegated spending.
contract LoomHandler is Test {
    Loom internal immutable token;
    address[3] public actors;

    constructor(Loom token_) {
        token = token_;
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2")];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, token.INITIAL_SUPPLY());
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        address to = actors[toSeed % 3];
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 amount = bound(rawAmount, 0, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

contract LoomInvariantTest is Test {
    Loom internal token;
    LoomHandler internal handler;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new Loom();
        handler = new LoomHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LoomHandler.transfer.selector;
        selectors[1] = LoomHandler.approve.selector;
        selectors[2] = LoomHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 held;
        for (uint256 i; i < 3; ++i) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(held, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
