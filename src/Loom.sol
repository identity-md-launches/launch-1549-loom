// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Loom's immutable fixed-supply ERC-20. The deploying caller receives all tokens.
contract Loom is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev No parameters or initialization calls are required. In a factory launch,
    /// msg.sender is the factory, which receives the entire supply for distribution.
    constructor() ERC20("Loom", "LOOM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
