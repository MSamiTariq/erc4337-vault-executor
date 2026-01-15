import { expect } from "chai";
import { ethers } from "hardhat";
import {
  TestEntryPoint,
  MinimalAccount,
  MockToken,
  MockVault4626,
  VaultExecutor,
} from "../typechain-types";

describe("ERC-4337 Smart Account Vault Executor", function () {
  let entryPoint: TestEntryPoint;
  let token: MockToken;
  let vault: MockVault4626;
  let executor: VaultExecutor;
  let account: MinimalAccount;

  let owner: any;
  let bundler: any;

  beforeEach(async () => {
    [owner, bundler] = await ethers.getSigners();

    // Deploy TestEntryPoint (simplified EntryPoint for testing)
    // Note: The real EntryPoint from @account-abstraction/contracts requires Cancun EVM
    // features (transient storage) and is more complex. TestEntryPoint provides the
    // essential functionality needed for testing.
    const EntryPointFactory = await ethers.getContractFactory("TestEntryPoint");
    entryPoint = (await EntryPointFactory.deploy()) as TestEntryPoint;
    await entryPoint.waitForDeployment();

    // Deploy token + vault + executor
    const Token = await ethers.getContractFactory("MockToken");
    token = (await Token.deploy()) as MockToken;
    await token.waitForDeployment();

    const Vault = await ethers.getContractFactory("MockVault4626");
    vault = (await Vault.deploy(await token.getAddress())) as MockVault4626;
    await vault.waitForDeployment();

    const Exec = await ethers.getContractFactory("VaultExecutor");
    executor = (await Exec.deploy()) as VaultExecutor;
    await executor.waitForDeployment();

    // Deploy minimal account
    const Account = await ethers.getContractFactory("MinimalAccount");
    account = (await Account.deploy(owner.address, await entryPoint.getAddress())) as MinimalAccount;
    await account.waitForDeployment();

    // Fund account with ETH for gas prefund, and mint tokens to account for deposit
    await owner.sendTransaction({ to: await account.getAddress(), value: ethers.parseEther("1") });
    await token.mint(await account.getAddress(), ethers.parseEther("100"));
  });

  it("executes approve+deposit into ERC-4626 via UserOperation", async () => {
    const accountAddr = await account.getAddress();
    const epAddr = await entryPoint.getAddress();
    const execAddr = await executor.getAddress();
    const tokenAddr = await token.getAddress();
    const vaultAddr = await vault.getAddress();

    const depositAmount = ethers.parseEther("10");

    // Encode call: executor.approveAndDeposit(token, vault, amount, receiver=account)
    const iface = new ethers.Interface([
      "function approveAndDeposit(address asset,address vault,uint256 assets,address receiver) returns (uint256 shares)",
    ]);
    const execCallData = iface.encodeFunctionData("approveAndDeposit", [
      tokenAddr,
      vaultAddr,
      depositAmount,
      accountAddr,
    ]);

    // Account.execute(target=executor, value=0, data=execCallData)
    const accountIface = new ethers.Interface([
      "function execute(address target,uint256 value,bytes data)",
    ]);
    const callData = accountIface.encodeFunctionData("execute", [execAddr, 0, execCallData]);

    // Build a minimal PackedUserOperation
    // NOTE: In production you’d use a bundler; in tests we call entryPoint.handleOps directly.
    const nonce = await entryPoint.getNonce(accountAddr, 0);

    const userOp: any = {
      sender: accountAddr,
      nonce,
      initCode: "0x",
      callData,
      accountGasLimits: ethers.zeroPadValue("0x", 32), // we'll set via helper below
      preVerificationGas: 100000,
      gasFees: ethers.zeroPadValue("0x", 32), // set below
      paymasterAndData: "0x",
      signature: "0x",
    };

    // Set gas fields (Packed format: accountGasLimits = verificationGasLimit(16 bytes) + callGasLimit(16 bytes))
    const verificationGasLimit = 500000;
    const callGasLimit = 500000;
    userOp.accountGasLimits = ethers.concat([
      ethers.zeroPadValue(ethers.toBeHex(verificationGasLimit), 16),
      ethers.zeroPadValue(ethers.toBeHex(callGasLimit), 16),
    ]);

    const maxFeePerGas = ethers.parseUnits("30", "gwei");
    const maxPriorityFeePerGas = ethers.parseUnits("2", "gwei");
    // Packed format: gasFees = maxPriorityFeePerGas(16 bytes) + maxFeePerGas(16 bytes)
    userOp.gasFees = ethers.concat([
      ethers.zeroPadValue(ethers.toBeHex(maxPriorityFeePerGas), 16),
      ethers.zeroPadValue(ethers.toBeHex(maxFeePerGas), 16),
    ]);

    // Get userOpHash from EntryPoint (EIP-712 hash) and sign it
    // The EntryPoint uses EIP-712, so we sign the hash directly
    const userOpHash = await entryPoint.getUserOpHash(userOp);
    // Sign the EIP-712 hash (EntryPoint already includes domain separator)
    const signature = await owner.signMessage(ethers.getBytes(userOpHash));
    userOp.signature = signature;

    // Execute op
    await entryPoint.connect(bundler).handleOps([userOp], bundler.address);

    // Validate vault deposit happened (account got shares)
    const shares = await vault.balanceOf(accountAddr);
    expect(shares).to.be.gt(0n);
  });

  it("rejects invalid signature", async () => {
    const accountAddr = await account.getAddress();
    const execAddr = await executor.getAddress();
    const tokenAddr = await token.getAddress();
    const vaultAddr = await vault.getAddress();

    const depositAmount = ethers.parseEther("1");

    const iface = new ethers.Interface([
      "function approveAndDeposit(address asset,address vault,uint256 assets,address receiver) returns (uint256 shares)",
    ]);
    const execCallData = iface.encodeFunctionData("approveAndDeposit", [
      tokenAddr,
      vaultAddr,
      depositAmount,
      accountAddr,
    ]);

    const accountIface = new ethers.Interface([
      "function execute(address target,uint256 value,bytes data)",
    ]);
    const callData = accountIface.encodeFunctionData("execute", [execAddr, 0, execCallData]);

    const nonce = await entryPoint.getNonce(accountAddr, 0);

    const userOp: any = {
      sender: accountAddr,
      nonce,
      initCode: "0x",
      callData,
      accountGasLimits: ethers.concat([
        ethers.zeroPadValue(ethers.toBeHex(500000), 16),
        ethers.zeroPadValue(ethers.toBeHex(500000), 16),
      ]),
      preVerificationGas: 100000,
      gasFees: ethers.concat([
        ethers.zeroPadValue(ethers.toBeHex(ethers.parseUnits("2", "gwei")), 16),
        ethers.zeroPadValue(ethers.toBeHex(ethers.parseUnits("30", "gwei")), 16),
      ]),
      paymasterAndData: "0x",
      signature: "0x1234", // invalid
    };

    await expect(entryPoint.handleOps([userOp], owner.address)).to.be.reverted;
  });
});
