// scripts/redeploy.js
// Run with: npx hardhat run scripts/redeploy.js --network sepolia

const hre = require("hardhat");

async function main() {
  const SALE_TOKEN = "0x44860d6eAd25c3EDC6bD467dc7FDC81803870e00";
  const PAYMENT_TOKEN = "0x11986D505A1CAC8Ffb2A2F61123E095A682CFB9d";

  const TOKEN_PRICE = 1000;
  const SOFT_CAP = "10000000000000000000";
  const HARD_CAP = "100000000000000000000";
  const MIN_PURCHASE = "100000000000000000";
  const MAX_PURCHASE = "5000000000000000000";

  // NOTE: pick fresh timestamps — your old SALE_START has likely already passed
  const now = Math.floor(Date.now() / 1000);
  const SALE_START = now + 5 * 60;
  const SALE_END = SALE_START + 7 * 24 * 60 * 60;

  const VESTING_DURATION = 2592000; // 30 days
  const TGE_PERCENT = 20;

  console.log("Deploying with:", {
    SALE_TOKEN, PAYMENT_TOKEN, TOKEN_PRICE, SOFT_CAP, HARD_CAP,
    MIN_PURCHASE, MAX_PURCHASE, SALE_START, SALE_END, VESTING_DURATION, TGE_PERCENT,
  });

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying from account:", deployer.address);

  const Presale = await hre.ethers.getContractFactory("presale");
  const presale = await Presale.deploy(
    SALE_TOKEN, PAYMENT_TOKEN, TOKEN_PRICE, SOFT_CAP, HARD_CAP,
    MIN_PURCHASE, MAX_PURCHASE, SALE_START, SALE_END, VESTING_DURATION, TGE_PERCENT
  );

  await presale.waitForDeployment();
  console.log("New presale deployed to:", await presale.getAddress());
}

main().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});