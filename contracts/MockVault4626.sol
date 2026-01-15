// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Simplified mock "ERC-4626-like" vault.
 *
 * - Tracks shares 1:1 with deposited assets
 * - Pulls tokens from the receiver using allowance
 *   (the executor gives the vault allowance from the smart account)
 */
contract MockVault4626 {
    IERC20 public immutable asset;

    mapping(address => uint256) public balanceOf;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // For testing purposes, we only track shares and don't move underlying tokens.
        balanceOf[receiver] += assets;
        shares = assets;
    }
}
