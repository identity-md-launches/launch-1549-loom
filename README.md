# Loom (LOOM)

Loom is an immutable ERC-20 with 18 decimals and a fixed supply of
1,000,000,000 LOOM, or **1000000000000000000000000000** base units.
The constructor mints the entire supply once to `msg.sender`.

## Build and verify

Run from the repository root with Foundry installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimizer (200 runs), and
`bytecode_hash = "none"`. The compiler must be installed in the verification
environment. Solidity dependencies and test helpers are vendored under `lib/`,
with versions and licenses documented in `lib/DEPENDENCIES.md`; no network is
needed once Foundry and the pinned compiler are available.

## Deployment parameters

- Contract: `src/Loom.sol:Loom` (Solidity identifier `Loom`).
- Constructor arguments: none; encoded arguments are empty.
- Name: `Loom`; symbol: `LOOM`; decimals: `18`.
- Total supply in base units: `1000000000000000000000000000`.
- Initial recipient: the caller that creates the contract. A factory deployment
  gives the whole supply to the factory, rather than the transaction origin.
- Initialization or post-launch settings: none. No external contracts are called
  during construction, and there are no linked external libraries.

The assigned Ethereum launch uses the network's factory. Distribution, liquidity
creation, and the launch manifest are the launch system's responsibility. This
project supplies token bytecode and does not perform deployment transactions or
write a launch manifest. The token itself has no chain-specific configuration.

## Behavior and assumptions

The brief requests a plain token, so transfers move the exact amount with no taxes,
rebases, transfer hooks, or restrictions. Transfers of zero are supported and emit
`Transfer`; transfers to the zero address revert. Approvals replace the caller's
existing allowance and emit `Approval`. Delegated transfers consume finite
allowances; the ERC-20 implementation preserves an allowance of `uint256.max`.
Reverted transfers also roll back allowance changes. OpenZeppelin v5 does not
emit `Approval` when `transferFrom` consumes an allowance.

There is no owner, admin, minting entrypoint, burn entrypoint, pause, blacklist,
upgrade mechanism, permit, or asset recovery function. No party, including the
deployer, can mint more supply or move another holder's tokens without approval.
The token performs no external calls during transfers. Native ETH sent through a
normal call reverts; assets transferred directly to the token contract cannot be
recovered by an administrator.

## Operational responsibilities

The deployer must check the bytecode, metadata, supply, and constructor recipient
before launch and arrange the intended distribution. After launch there are no
administrative settings or maintenance transactions. Holders manage custody and
approvals; they should approve only what they need and revoke unused allowances.
When replacing a nonzero allowance, first set it to zero and wait for confirmation
to mitigate the ERC-20 allowance replacement race. Integrators must account for
18 decimals and track finite allowance consumption through storage reads.

Tests cover metadata, mint events, deployment through a factory, exact distribution
and onward transfer, balance and allowance errors, zero addresses and amounts,
self-transfers, allowance exhaustion/revocation, unlimited approvals, revert
atomicity, and absent privileged entrypoints. Fuzz tests cover valid transfers and
overdrafts. Stateful invariants verify fixed supply and conservation of balances
through randomized transfer, approve, and delegated-transfer sequences.

These local tests are not a security audit. The launch operator is responsible for
independent adversarial review and deployed-source verification before release.
