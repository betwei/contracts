import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import {Betwei, VRFCoordinatorV2Mock } from '../typechain-types'

type Deploy = {
  betwei: Betwei,
  hardhatVrfCoordinatorV2Mock: VRFCoordinatorV2Mock ,
  owner: any,
  otherAccount:any 
}

describe("Betwei test", function () {

  async function deployOneYearLockFixture() : Promise<Deploy> {
    const [owner, otherAccount] = await ethers.getSigners();

    let vrfCoordinatorV2Mock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
    const Betwei = await ethers.getContractFactory("Betwei");

    let hardhatVrfCoordinatorV2Mock = await vrfCoordinatorV2Mock.deploy(0, 0);

    await hardhatVrfCoordinatorV2Mock.createSubscription();

    await hardhatVrfCoordinatorV2Mock.fundSubscription(1, ethers.utils.parseEther("7"))

    const betwei = await Betwei.deploy(1, "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc", hardhatVrfCoordinatorV2Mock.address);

    return { betwei, hardhatVrfCoordinatorV2Mock, owner, otherAccount };
  }
  it("Contract should request Random numbers successfully", async () => {
    const {betwei, hardhatVrfCoordinatorV2Mock, owner} : Deploy = await deployOneYearLockFixture();

    let txGenerateRandoms = await betwei.requestRandomWords();

    let { events } = await txGenerateRandoms.wait();

    expect(await betwei.s_requestId()).to.equal(1);

    // TODO capture event and get reqId
    // let { reqId:any } = events.filter( x => x.event === 'Event Request name')[0].args;
    const reqId = 1;

    await expect(
       hardhatVrfCoordinatorV2Mock.fulfillRandomWords(reqId, betwei.address)
    ).to.emit(hardhatVrfCoordinatorV2Mock, "RandomWordsFulfilled")

    // random number
    expect(await betwei.s_randomWords(0)).to.greaterThan(0)
    expect(await betwei.s_randomWords(1)).to.greaterThan(0)

  });
});
