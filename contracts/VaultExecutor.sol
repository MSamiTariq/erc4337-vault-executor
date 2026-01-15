// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Minimal vault interface used by the executor.
 * Any vault implementing this function can be used.
 */
interface IVaultLike {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

/**
 * A helper called by the smart account (via execute)
 * to approve and deposit into a vault in one call.
 *
 * Flow:
 * - msg.sender is the smart account
 * - this contract approves the vault to pull tokens from the account
 * - the vault's deposit() pulls tokens from the account (receiver)
 */
contract VaultExecutor {
    function approveAndDeposit(
        IERC20 asset,
        IVaultLike vault,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        // msg.sender is the smart account. Approve the vault to pull from it.
        asset.approve(address(vault), assets);
        shares = vault.deposit(assets, receiver);
    }
}
