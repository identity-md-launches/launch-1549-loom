// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Loom} from "../src/Loom.sol";

contract LoomFactoryProbe {
    function deploy() external returns (Loom) {
        return new Loom();
    }

    function distribute(Loom token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract LoomTest is Test {
    Loom internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Loom();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Loom");
        assertEq(token.symbol(), "LOOM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsSingleMint() public {
        vm.recordLogs();
        Loom deployed = new Loom();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "constructor must mint exactly once");
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_FactoryReceivesEntireSupplyAndDistributesWithoutFees() public {
        LoomFactoryProbe factory = new LoomFactoryProbe();
        vm.prank(alice, alice);
        Loom launched = factory.deploy();
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(alice), 0, "tx.origin must not receive the constructor mint");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        assertTrue(factory.distribute(launched, alice, swarm));
        assertTrue(factory.distribute(launched, bob, pool));
        assertTrue(factory.distribute(launched, spender, SUPPLY - swarm - pool));
        assertEq(launched.balanceOf(alice), swarm);
        assertEq(launched.balanceOf(bob), pool);
        assertEq(launched.balanceOf(spender), SUPPLY / 10);
        assertEq(launched.balanceOf(address(factory)), 0);
        vm.prank(alice);
        assertTrue(launched.transfer(address(this), swarm));
        assertEq(launched.balanceOf(address(this)), swarm);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 10 ether);
        assertTrue(token.transfer(alice, 10 ether));
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveEmitsEventAndCanReplaceOrRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 10 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(spender, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), bob, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
    }

    function test_ExactAllowanceExhaustedAndCannotReuse() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 10 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_InfiniteAllowanceRemainsUnchanged() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 10 ether));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_ZeroTransferFromWithoutAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_TransferFromToSelfStillConsumesAllowance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_RevertTransferFromWithoutAllowanceEvenByDeployer() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertInsufficientAllowancePreservesState() public {
        token.approve(spender, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3 ether, 4 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 4 ether);
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferFromToZeroRollsBackAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferFromZeroSender() public {
        // Allowance bookkeeping rejects the zero owner before the transfer executes.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function test_NoMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(alice, 10 ether);
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[7] = abi.encodeWithSignature("initialize(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_RevertNativeEtherAndUnknownSelector() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransfer(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, allowance);
        token.approve(spender, allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), allowance - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdraftAlwaysReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
