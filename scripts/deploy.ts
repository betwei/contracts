import { ethers } from "hardhat";
import * as dotenv from 'dotenv';
dotenv.config();


const SUBSCRIPTION_ID  = process.env.SUBSCRIPTION_ID ? parseInt(process.env.SUBSCRIPTION_ID) : -1;

async function main() {
  if (!SUBSCRIPTION_ID || SUBSCRIPTION_ID <= 0) {
    throw new Error('No valid subscription id');
  }

  const Betwei = await ethers.getContractFactory("Betwei");
  const betwei = await Betwei.deploy(SUBSCRIPTION_ID);

  await betwei.deployed();

  console.log('Contract deployed, address', betwei.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
