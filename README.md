# ERC-4337 Vault Executor

A learning project demonstrating **ERC-4337 Account Abstraction** by implementing a smart account that can execute complex operations (like approving and depositing into ERC-4626 vaults) through UserOperations.

## 🎯 What This Project Does

This project shows how to:
- Create a **Smart Account** (contract wallet) that acts as your wallet
- Execute transactions via **UserOperations** instead of regular transactions
- Perform complex operations (approve + deposit) in a single UserOperation
- Understand the **EntryPoint**, **Bundler**, and **Alt Mempool** concepts

### Example Use Case

Instead of sending two separate transactions:
1. `token.approve(vault, amount)`
2. `vault.deposit(amount, receiver)`

You can send a **single UserOperation** that executes both operations atomically through your smart account.

## 📚 Understanding ERC-4337

### Key Concepts

- **Smart Account**: A smart contract that acts as your wallet (replaces EOA)
- **UserOperation**: A transaction-like object describing what you want to do
- **EntryPoint**: The singleton contract that validates and executes UserOperations
- **Bundler**: A service that collects UserOperations and submits them to the EntryPoint
- **Alt Mempool**: A separate mempool for UserOperations (not regular transactions)

### How It Works

```
1. User creates UserOperation: "I want to deposit tokens into vault"
   ↓
2. User signs the UserOperation
   ↓
3. User sends to Bundler (or directly to EntryPoint in tests)
   ↓
4. Bundler calls EntryPoint.handleOps([userOp])
   ↓
5. EntryPoint validates signature via account.validateUserOp()
   ↓
6. EntryPoint executes via account.execute()
   ↓
7. Account calls VaultExecutor.approveAndDeposit()
   ↓
8. Tokens are approved and deposited atomically ✓
```

## 🏗️ Project Structure

```
contracts/
├── MinimalAccount.sol      # Smart Account implementation
├── VaultExecutor.sol       # Helper contract for approve+deposit
├── TestEntryPoint.sol      # Simplified EntryPoint for testing
├── MockToken.sol           # ERC-20 token for testing
└── MockVault4626.sol      # ERC-4626 vault for testing

test/
└── erc4337-vault-executor.test.ts  # Integration tests
```

## 🔧 Contracts Overview

### MinimalAccount.sol

A minimal ERC-4337 smart account that:
- Stores an owner address (EOA)
- Validates UserOperation signatures
- Executes arbitrary calls (only via EntryPoint)
- Implements the `IAccount` interface

**Key Functions:**
- `validateUserOp()`: Validates the UserOperation signature
- `execute()`: Executes arbitrary calls (protected by `onlyEntryPoint`)

### VaultExecutor.sol

A helper contract that combines token approval and vault deposit in one call:
- Approves the vault to spend tokens from the smart account
- Calls `vault.deposit()` which pulls tokens from the account
- Returns the shares received

### TestEntryPoint.sol

**⚠️ Important**: This is a **simplified EntryPoint for testing only**.

**Why not use the real EntryPoint?**
- The real EntryPoint requires **Cancun EVM features** (transient storage: `tload`/`tstore`)
- It's a complex production contract with gas accounting, paymasters, aggregators, etc.
- For testing, we only need: nonce tracking, userOpHash computation, and execution

**Differences from Real EntryPoint:**
- Uses simple `keccak256` for `getUserOpHash` (real one uses EIP-712 with domain separator)
- Minimal gas accounting (real one has sophisticated prefunding/refunding)
- No paymaster support (real one supports paymasters)
- No aggregator support (real one supports signature aggregators)

**For Production**: Deploy the real EntryPoint from `@account-abstraction/contracts`.

## 🧪 Testing

### Why No Bundler in Tests?

In production, the flow is:
```
User → Bundler → EntryPoint → Account
```

In tests, we simplify to:
```
Test → EntryPoint → Account
```

**Reasons:**
1. **Simplicity**: Tests focus on the core logic, not bundler infrastructure
2. **Speed**: Direct calls are faster than simulating bundler behavior
3. **Control**: We can directly test EntryPoint and Account interactions

The test directly calls `entryPoint.handleOps()` instead of going through a bundler. In production, you'd send UserOperations to a bundler's alt mempool.

### Running Tests

```bash
# Run all tests
npx hardhat test

# Run with gas reporting
REPORT_GAS=true npx hardhat test

# Run specific test file
npx hardhat test test/erc4337-vault-executor.test.ts
```

### Test Flow

1. **Setup**: Deploy EntryPoint, Account, Token, Vault, Executor
2. **Create UserOperation**: Encode the desired operation (approve + deposit)
3. **Sign**: Get `userOpHash` from EntryPoint and sign it
4. **Execute**: Call `entryPoint.handleOps([userOp])`
5. **Verify**: Check that tokens were deposited and shares were received

## 🚀 Getting Started

### Prerequisites

- Node.js >= 18
- npm or yarn

### Installation

```bash
# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test
```

### Environment Setup

Create a `.env` file (optional, for network configuration):

```env
SEPOLIA_RPC_URL=your_rpc_url
PRIVATE_KEY=your_private_key
```

## 📖 Key Learnings

### 1. Smart Account Deployment

Each user gets their own smart account contract instance. In production, this is typically done via:
- **Factory Pattern**: Deploy accounts on-demand
- **CREATE2**: Deterministic addresses (same owner → same address)
- **InitCode**: Deploy account in the same UserOperation

### 2. UserOperation Structure

```typescript
{
  sender: accountAddress,        // Your smart account
  nonce: currentNonce,          // Prevents replay attacks
  initCode: "0x",               // Account deployment code (if new)
  callData: encodedCall,        // What to execute
  accountGasLimits: packed,      // Gas limits
  preVerificationGas: 100000,    // Gas for validation
  gasFees: packed,               // maxFeePerGas, maxPriorityFeePerGas
  paymasterAndData: "0x",       // Paymaster (if using)
  signature: signature           // Your signature
}
```

### 3. Signature Validation

1. EntryPoint computes `userOpHash` from UserOperation fields
2. User signs the `userOpHash` with their private key
3. Account's `validateUserOp()` recovers the signer and checks it matches the owner

### 4. Replay Attack Prevention

- **Nonce**: Each UserOperation must use the current nonce
- **Nonce in Hash**: Nonce is part of the signed hash
- **Auto-increment**: EntryPoint increments nonce after execution
- **Chain ID**: Real EntryPoint includes chainId in hash (prevents cross-chain replay)

## 🔮 Future Enhancements

### EIP-7579: Modular Smart Accounts

**What it is**: A standard for modular smart account architecture where accounts can be composed of multiple modules.

**How it would enhance this project**:
- **Validation Module**: Separate signature validation logic
- **Execution Module**: Separate execution logic
- **Hook Module**: Add pre/post execution hooks
- **Plugin System**: Install/remove functionality without redeploying account

**Example**:
```solidity
// Instead of hardcoded ECDSA validation
account.installModule(ECDSAValidationModule);

// Add new functionality
account.installModule(SessionKeyModule);  // Allow session keys
account.installModule(RecoveryModule);   // Add recovery mechanism
```

### EIP-7540: Native Account Abstraction

**What it is**: Account abstraction built directly into the Ethereum protocol (no EntryPoint needed).

**How it would enhance this project**:
- **No EntryPoint**: Transactions are natively UserOperations
- **Protocol-level**: No need for bundlers or alt mempools
- **Better UX**: Seamless experience, no infrastructure layer
- **Lower Gas**: Protocol-level optimizations

**Impact**: This would make ERC-4337 obsolete, but the concepts (smart accounts, UserOperations) remain the same.

### EIP-7683: Generalized Execution Layer

**What it is**: A standard for cross-chain and generalized execution, allowing UserOperations to execute across multiple chains or execution environments.

**How it would enhance this project**:
- **Cross-chain Operations**: Deposit on one chain, execute on another
- **Multi-chain Vaults**: Interact with vaults across chains in one UserOperation
- **Generalized Execution**: Execute in different environments (L2s, sidechains)

**Example**:
```solidity
UserOperation {
  // Execute on multiple chains
  executionLayers: [mainnet, arbitrum, optimism],
  callData: [
    approveOnMainnet(),
    depositOnArbitrum(),
    stakeOnOptimism()
  ]
}
```

## 📚 Resources

- [ERC-4337 Specification](https://eips.ethereum.org/EIP-4337)
- [Account Abstraction Docs](https://account-abstraction.gitbook.io/)
- [@account-abstraction/contracts](https://github.com/eth-infinitism/account-abstraction)
- [EIP-7579: Modular Smart Accounts](https://eips.ethereum.org/EIP-7579)
- [EIP-7540: Native Account Abstraction](https://eips.ethereum.org/EIP-7540)
- [EIP-7683: Generalized Execution Layer](https://eips.ethereum.org/EIP-7683)

## 🤝 Contributing

This is a learning project. Feel free to:
- Experiment with different account implementations
- Add more complex operations
- Implement paymaster support
- Add signature aggregation
- Explore the future EIPs mentioned above

## 📝 License

ISC

## 🙏 Acknowledgments

Built using:
- [@account-abstraction/contracts](https://github.com/eth-infinitism/account-abstraction)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [Hardhat](https://hardhat.org/)
