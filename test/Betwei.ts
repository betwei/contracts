import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from 'ethers';
import {Betwei, VRFCoordinatorV2Mock } from '../typechain-types'

type Deploy = {
  betwei: Betwei,
  hardhatVrfCoordinatorV2Mock: VRFCoordinatorV2Mock ,
  owner: any,
  otherAccount:any 
}

describe("Betwei test", function () {

  async function deployBetWai() : Promise<Deploy> {
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
    const {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      owner
    } : Deploy = await deployBetWai();

    let { events } = await requestNewRandomNumbers(betwei);

    expect(await betwei.s_requestId()).to.equal(1);

    // TODO capture event and get reqId
    // let { reqId:any } = events.filter( x => x.event === 'Event Request name')[0].args;
    const reqId = 1;

    await expect(
       hardhatVrfCoordinatorV2Mock.fulfillRandomWords(reqId, betwei.address)
    ).to.emit(hardhatVrfCoordinatorV2Mock, "RandomWordsFulfilled")

    // random number
    expect(await getRandomNumber(betwei, 0)).to.greaterThan(0)
    expect(await getRandomNumber(betwei, 1)).to.greaterThan(0)

  });

  it("Generate new bet", async () => {
    const {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      owner,
      otherAccount
    } : Deploy = await deployBetWai();

    // max duration (players)
    // type 0 random winner
    let { events }  = await betwei.createNewGame(0, 2);
    let { gameId:any } = events.filter( x => x.event === 'NewGameCreated')[0].args;

    expect(gameId).to.equal(1);

    await expect(
       betwei.connect(otherAccount).enrollToGame(gameId)
    ).to.emit(betwei, "EnrolledToGame")

  })

  /**
   * Functions
   */
  async function requestNewRandomNumbers(betwei: Betwei) {

    let txGenerateRandoms = await betwei.requestRandomWords();

    return txGenerateRandoms.wait();
  }

  async function getRandomNumber(betwei: Betwei, index: Number) {
    return betwei.s_randomWords(BigNumber.from(index));
  }

});
