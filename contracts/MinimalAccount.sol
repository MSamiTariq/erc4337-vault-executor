// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * Minimal ERC-4337 account:
 * - owner EOA signature
 * - validateUserOp per ERC-4337
 * - execute only callable by EntryPoint
 */
contract MinimalAccount is IAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public owner;
    address public immutable entryPoint;

    error NotEntryPoint();
    error NotOwner();

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _owner, address _entryPoint) {
        owner = _owner;
        entryPoint = _entryPoint;
    }

    receive() external payable {}

    function setOwner(address newOwner) external onlyOwner {
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /**
     * Execute an arbitrary call. Must be called through EntryPoint as part of a UserOp.
     */
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPoint {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            // bubble revert
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /**
     * ERC-4337 validation:
     * Return 0 if valid, else SIG_VALIDATION_FAILED (1).
     * Also prefund missing funds if needed.
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        // Signature is over userOpHash using eth_sign (EIP-191)
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address signer = ethHash.recover(userOp.signature);

        if (signer != owner) {
            return 1; // SIG_VALIDATION_FAILED
        }

        // Prefund if needed
        if (missingAccountFunds > 0) {
            (bool ok, ) = payable(msg.sender).call{value: missingAccountFunds}("");
            ok; // ignore failure -> EntryPoint will revert if not enough
        }

        return 0;
    }
}
