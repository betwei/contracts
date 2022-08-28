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
    "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc" // rinkeby
    "0x6168499c0cFfCaCD319c818142124B7A15E857ab" // rinkeby
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
