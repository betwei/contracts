import { HardhatRuntimeEnvironment } from "hardhat/types"
import { task } from "hardhat/config";
import * as dotenv from 'dotenv';
dotenv.config();

const SUBSCRIPTION_ID  = process.env.SUBSCRIPTION_ID ? parseInt(process.env.SUBSCRIPTION_ID) : -1;
const CHAINLINK_GOERLI_KEYHASH = "0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15";
const CHAINLINK_GOERLI_COORDINATOR = "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D";

task('cverify', 'Verify smart contract')
    .addPositionalParam('address', 'Contract address')
    .setAction(async ( { address }: { address : string }, env: HardhatRuntimeEnvironment) => {
        if (!SUBSCRIPTION_ID || SUBSCRIPTION_ID <= 0) {
            throw new Error('No valid subscription id');
        }

        const { abi } = env.artifacts.readArtifactSync("Betwei")

        const betwei = new env.ethers.Contract(address, abi);

        console.log('Verifying contract', address) 
        await env.run('verify:verify', {
            address: betwei.address,
            constructorArguments: [
              SUBSCRIPTION_ID,
              CHAINLINK_GOERLI_KEYHASH,
              CHAINLINK_GOERLI_COORDINATOR
            ]

        });
    })
