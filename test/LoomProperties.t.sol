// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Loom} from "../src/Loom.sol";

/// @dev Complements the original examples with arithmetic boundaries, approval
/// isolation, and failure atomicity. Amounts are always token minor units.
/// forge-config: default.fuzz.runs = 1000
contract LoomPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Loom internal token;
    address internal alice = makeAddr("property-alice");
    address internal bob = makeAddr("property-bob");
    address internal spender = makeAddr("property-spender");

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Loom();
    }

    function test_OneMinorUnitIsTransferredExactly() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAndOverdrawnSelfTransferRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumApprovalDoesNotBypassBalanceCheck() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneApprovalIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_UnlimitedAllowanceSurvivesRepeatedFullBalanceSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        for (uint256 i; i < 3; ++i) {
            vm.prank(spender);
            assertTrue(token.transferFrom(address(this), alice, SUPPLY));
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(alice), SUPPLY);
            assertEq(token.allowance(address(this), spender), type(uint256).max);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), SUPPLY));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevokingUnlimitedApprovalImmediatelyStopsSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ReducedApprovalReplacesRemainingSpendingPower() public {
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4));
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 6);
        assertEq(token.balanceOf(address(this)), SUPPLY - 6);
    }

    function test_HolderNeedsSelfApprovalForTransferFrom() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_ApprovalCannotBeDelegatedToAnotherSpender() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.approve(bob, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(spender, bob), 10);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_ZeroValueCallsStillRejectInvalidAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        // An approval is independent of the owner's balance and other approval pairs.
        vm.prank(bob);
        assertTrue(token.approve(spender, 17));
        vm.startPrank(alice);
        assertTrue(token.approve(bob, 23));
        assertTrue(token.approve(spender, first));
        assertEq(token.allowance(alice, spender), first);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), 23);
        assertEq(token.allowance(bob, spender), 17);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSpendingSupportsFullAllowanceRange(uint256 allowance, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, allowance < SUPPLY ? allowance : SUPPLY);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(
            token.allowance(address(this), spender), allowance == type(uint256).max ? allowance : allowance - amount
        );
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceFailureIsAtomic(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 allowance = bound(rawAllowance, 0, amount - 1);
        assertTrue(token.approve(spender, allowance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedOverdraftIsAtomic(uint256 rawBalance, uint256 rawAmount, bool unlimited, bool self)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        uint256 allowance = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowance));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, self ? alice : bob, amount);
        assertEq(token.allowance(alice, spender), allowance);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroRecipientFailureIsAtomic(uint256 rawAmount, bool unlimited) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowance = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(spender, allowance));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndPreservesApproval(uint256 rawBalance, uint256 rawAmount)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), balance - amount);
        assertEq(token.balanceOf(bob), amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AnyNonzeroRecipientReceivesExactAmount(uint160 rawRecipient, uint256 rawAmount) public {
        address recipient = address(uint160(bound(uint256(rawRecipient), 1, type(uint160).max)));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 beforeBalance = token.balanceOf(recipient);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, amount);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), beforeBalance + amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
