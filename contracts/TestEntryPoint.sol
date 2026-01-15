// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";

/**
 * Minimal test-only EntryPoint implementation.
 * 
 * Why not use the real EntryPoint from the account-abstraction library?
 * - The real EntryPoint requires Cancun EVM features (transient storage: tload/tstore)
 * - It's a complex production contract with gas accounting, paymasters, aggregators, etc.
 * - For testing, we only need: nonce tracking, userOpHash computation, and execution
 * 
 * Differences from real EntryPoint:
 * - Real EntryPoint uses EIP-712 for getUserOpHash (includes EntryPoint address + chainId)
 * - This TestEntryPoint uses simple keccak256 (simpler for tests, but not spec-compliant)
 * - Real EntryPoint has sophisticated gas accounting, this one is minimal
 * 
 * This is NOT a full ERC-4337 EntryPoint implementation and should only be used in tests.
 * For production, deploy the real EntryPoint from the account-abstraction contracts package.
 */
contract TestEntryPoint {
    mapping(address => uint256) public nonces;

    function getNonce(address sender, uint192 /* key */ ) external view returns (uint256) {
        return nonces[sender];
    }

    function getUserOpHash(
        PackedUserOperation calldata userOp
    ) public pure returns (bytes32) {
        // Simple, deterministic hash over all UserOp fields
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                userOp.initCode,
                userOp.callData,
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                userOp.paymasterAndData
            )
        );
    }

    function handleOps(
        PackedUserOperation[] calldata ops,
        address payable beneficiary
    ) external {
        // beneficiary is unused in this minimal test implementation
        beneficiary;

        for (uint256 i = 0; i < ops.length; i++) {
            PackedUserOperation calldata op = ops[i];

            bytes32 userOpHash = getUserOpHash(op);

            // Bump nonce for the sender
            nonces[op.sender] = uint256(op.nonce) + 1;

            // Call account validation (will revert if invalid)
            IAccount(op.sender).validateUserOp(op, userOpHash, 0);

            // Execute the account's callData, bubbling up any revert reason
            (bool ok, bytes memory ret) = op.sender.call(op.callData);
            if (!ok) {
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
    }
}


