import { ethers } from "hardhat";
import * as dotenv from 'dotenv';
dotenv.config();


const SUBSCRIPTION_ID  = process.env.SUBSCRIPTION_ID ? parseInt(process.env.SUBSCRIPTION_ID) : -1;

async function main() {
  if (!SUBSCRIPTION_ID || SUBSCRIPTION_ID <= 0) {
    throw new Error('No valid subscription id');
  }

  const Betwei = await ethers.getContractFactory("Betwei");
  // supported networks VRF
  // https://docs.chain.link/docs/vrf/v2/supported-networks/#configurations
  const betwei = await Betwei.deploy(
    SUBSCRIPTION_ID,
    "0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15",
    "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D" // Goerli
  );

  await betwei.deployed();

  console.log('Contract deployed, address', betwei.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
