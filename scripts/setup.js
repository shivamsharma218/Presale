// scripts/setup.js
// Run with: npx hardhat run scripts/setup.js --network sepolia
//
// This script (using the deployer/owner wallet, since it holds both tokens):
//   1. Approves the presale contract to pull SALE_TOKEN from the deployer
//   2. Calls depositSaleTokens() to fund the presale with sale tokens
//   3. Approves the presale contract to pull PAYMENT_TOKEN (mUSDT) from the
//      deployer, so the SAME wallet can also test-buy via buyTokens()
//
// EDIT the constants below to match your deployment.

const hre = require("hardhat");

const PRESALE_ADDRESS = "0x11fA8c8cC9927Ae818d036ea82bd664D25971F57"; // <-- your deployed presale
const SALE_TOKEN = "0x44860d6eAd25c3EDC6bD467dc7FDC81803870e00";
const PAYMENT_TOKEN = "0x11986D505A1CAC8Ffb2A2F61123E095A682CFB9d"; // mUSDT

// How many sale tokens to deposit into the presale contract.
// EDIT: must be enough to cover totalTokensSold + ~5% referral headroom.
const DEPOSIT_AMOUNT = hre.ethers.parseUnits("40000", 18); // <-- EDIT (match saleToken decimals)

// How much mUSDT to approve for test purchases from this same wallet.
// EDIT: set to whatever you plan to test-buy with, or 0 to skip this step.
const PAYMENT_APPROVE_AMOUNT = hre.ethers.parseUnits("100", 18); // <-- EDIT (match paymentToken decimals)

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
];

async function main() {
  const [signer] = await hre.ethers.getSigners();
  console.log("Using wallet:", signer.address);

  const saleToken = new hre.ethers.Contract(SALE_TOKEN, ERC20_ABI, signer);
  const paymentToken = new hre.ethers.Contract(PAYMENT_TOKEN, ERC20_ABI, signer);
  const presale = await hre.ethers.getContractAt("presale", PRESALE_ADDRESS, signer);

  // ---- 1. Approve sale token for deposit ----
  console.log(`Approving presale to pull ${DEPOSIT_AMOUNT.toString()} sale tokens...`);
  const approveTx1 = await saleToken.approve(PRESALE_ADDRESS, DEPOSIT_AMOUNT);
  await approveTx1.wait();
  console.log("Sale token approval confirmed:", approveTx1.hash);

  // ---- 2. Deposit sale tokens into presale ----
  console.log("Depositing sale tokens into presale...");
  const depositTx = await presale.depositSaleTokens(DEPOSIT_AMOUNT);
  await depositTx.wait();
  console.log("Deposit confirmed:", depositTx.hash);

  // ---- 3. (Optional) Approve payment token for test purchases ----
  if (PAYMENT_APPROVE_AMOUNT > 0n) {
    console.log(`Approving presale to pull ${PAYMENT_APPROVE_AMOUNT.toString()} payment tokens (mUSDT)...`);
    const approveTx2 = await paymentToken.approve(PRESALE_ADDRESS, PAYMENT_APPROVE_AMOUNT);
    await approveTx2.wait();
    console.log("Payment token approval confirmed:", approveTx2.hash);
  }

  // ---- Sanity check ----
  const saleTokenBalance = await saleToken.balanceOf(PRESALE_ADDRESS);
  const saleInfo = await presale.getSaleInfo();
  console.log("Presale sale-token balance now:", saleTokenBalance.toString());
  console.log("getSaleInfo():", saleInfo);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });