import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from 'dotenv';
import './tasks/cverify'
dotenv.config();


const RINKEBY_PK_ADDRESS = process.env.RINKEBY_PK_ADDRESS || '';
const GOERLI_PK_ADDRESS = process.env.GOERLI_PK_ADDRESS || '';
const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';
const ALCHEMY_GOERLI_KEY = process.env.ALCHEMY_GOERLI_KEY || '';
const ETHERSCAN_APIKEY = process.env.ETHERSCAN_APIKEY || '';

const config: HardhatUserConfig = {
  solidity: "0.8.9",
  networks: {
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: RINKEBY_PK_ADDRESS ? [RINKEBY_PK_ADDRESS] : []
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_GOERLI_KEY}`,
      accounts: GOERLI_PK_ADDRESS ? [GOERLI_PK_ADDRESS] : []
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_APIKEY
  }
};

export default config;


