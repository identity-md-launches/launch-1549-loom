# Vendored dependencies

All imported sources and their licenses are stored as ordinary files; builds and tests
need no dependency downloads, submodules, package manager, or environment variables.

- `openzeppelin-contracts`: unmodified required source subset from OpenZeppelin Contracts
  tag `v5.0.2`, https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2.
  Includes ERC20, IERC20, IERC20Metadata, Context, IERC6093, and the upstream MIT license.
- `forge-std`: unmodified `src/` tree and licenses from tag `v1.9.7`,
  https://github.com/foundry-rs/forge-std/tree/v1.9.7. Used only by tests.

Remappings are explicit in the root `remappings.txt`.
