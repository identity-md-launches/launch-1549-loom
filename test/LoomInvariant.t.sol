// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Loom} from "../src/Loom.sol";

/// @dev Generates sequences among three holders, including self-transfers,
/// allowance replacement/revocation, finite or unlimited spending, and rejected calls.
/// The model is initialized from the required supply and updated from requested
/// actions, never from the token's reported balances or allowances.
contract LoomHandler is Test {
    Loom internal immutable token;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address[3] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Loom token_) {
        token = token_;
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2")];
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        // Approvals may exceed the supply; max-1 is finite, max is unlimited.
        _approve(owner, spender, unlimited ? type(uint256).max : rawAmount);
    }

    function revokeApproval(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], 0);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        address to = actors[toSeed % 3];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(rawAmount, 0, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _move(owner, to, amount);
    }

    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 3];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actors[toSeed % 3], amount);
    }

    function rejectDelegatedOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAmount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, actors[toSeed % 3], amount);
        // The model keeps the approval: a failed transfer must roll back spending it.
    }

    function rejectAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        _approve(owner, spender, amount - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 3]);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract LoomInvariantTest is Test {
    Loom internal token;
    LoomHandler internal handler;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new Loom();
        handler = new LoomHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        // Seed funded holders and both approval modes so delegated spending is
        // reachable from the start, without requiring a lucky random prefix.
        handler.transfer(0, 1, SUPPLY / 3);
        handler.transfer(0, 2, SUPPLY / 3);
        handler.approve(0, 1, SUPPLY, false);
        handler.approve(1, 2, 0, true);
        handler.approve(2, 0, SUPPLY, false);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = LoomHandler.transfer.selector;
        selectors[1] = LoomHandler.approve.selector;
        selectors[2] = LoomHandler.transferFrom.selector;
        selectors[3] = LoomHandler.revokeApproval.selector;
        selectors[4] = LoomHandler.rejectOverdraft.selector;
        selectors[5] = LoomHandler.rejectDelegatedOverdraft.selector;
        selectors[6] = LoomHandler.rejectAllowanceOverspend.selector;
        selectors[7] = LoomHandler.rejectZeroRecipient.selector;
        selectors[8] = LoomHandler.rejectZeroSpender.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_EachHolderHasExactlyItsExpectedBalance() public view {
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder balance diverged from model");
        }
    }

    function invariant_AllowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < 3; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 3; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance diverged from model"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            assertEq(token.allowance(owner, address(this)), 0);
            assertEq(token.allowance(owner, address(handler)), 0);
        }
    }
}
