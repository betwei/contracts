import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, utils } from 'ethers';
import {Betwei, VRFCoordinatorV2Mock } from '../typechain-types'

type Deploy = {
  betwei: Betwei,
  hardhatVrfCoordinatorV2Mock: VRFCoordinatorV2Mock ,
  owner: any,
  otherAccount:any 
}

type InitCreatedGame = {
  betwei: Betwei,
  hardhatVrfCoordinatorV2Mock: VRFCoordinatorV2Mock ,
  owner: any,
  otherAccount:any,
  gameId: BigNumber

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

  it("Success create new bet", async () => {
    const {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      owner,
      otherAccount
    } : Deploy = await deployBetWai();

    let { events, tx } = await createNewGame(betwei);

    await expect(
      tx
    ).to.emit(betwei, "NewGameCreated");

    let gameId = getGameIdFromCreatedEvent(events);

    // First game
    expect(gameId).to.equal(0);

    // status = OPEN
    expect(
       await betwei.gameStatus(gameId)
    ).to.equal(0);

    // empty winners
    expect(
       (await betwei.winners(gameId)).length
    ).to.equal(0);

  })

  it('Success enroll to game', async() => {
    // init contract and game
    let {
      betwei,
      gameId,
      owner,
      otherAccount
    } = await initContractAndGetGameId();

    // other account enrolling game
    // TODO verify event data
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)
    ).to.emit(betwei, "EnrolledToGame");

    //TODO check amount other account

  })

  it('Close in duration limit', async() => {

    let {
      betwei,
      gameId,
      owner,
      otherAccount
    } = await initContractAndGetGameId();

    // enroll otherAccount (creator account has enrolled)
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)
    ).to.emit(betwei, "EnrolledToGame");

    // two players enrolled
    expect(
       await betwei.connect(owner).usersEnrolled(gameId)
    ).to.equal(2);

    // close game
    expect(await betwei.connect(owner).closeGame(gameId)).to.be.ok;

    // status Game -> CLOSED
    expect(
       await betwei.gameStatus(gameId)
    ).to.equal(1);
  })

  it('Success finished game and check winners', async() => {

    let {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      gameId,
      owner,
      otherAccount
    } = await initContractAndGetGameId();

    // enroll otherAccount (creator account has enrolled)
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)
    ).to.emit(betwei, "EnrolledToGame");

    // two players enrolled
    expect(
       await betwei.connect(owner).usersEnrolled(gameId)
    ).to.equal(2);

    // close game
    expect(await betwei.connect(owner).closeGame(gameId)).to.be.ok;

    // status Game -> CLOSED
    expect(
       await betwei.gameStatus(gameId)
    ).to.equal(1);

    // go, start the game 
    expect(
       await betwei.connect(owner).startGame(gameId)
    ).to.be.ok;

    // CALCULATING
    expect(
       await betwei.gameStatus(gameId)
    ).to.equal(2);

    // Send random
    // first request.
    let fullFillRandoms = 
       await hardhatVrfCoordinatorV2Mock.fulfillRandomWords(1, betwei.address);

    await expect(
      fullFillRandoms
    ).to.emit(hardhatVrfCoordinatorV2Mock, "RandomWordsFulfilled")
    .to.emit(betwei, 'FinishGame')

    // status finished
    // TODO : no set?
    //expect(
    //   await betwei.gameStatus(gameId)
    //).to.equal(3);

    // winners 1
    let winners = await betwei.winners(gameId);
    expect(winners).to.have.lengthOf(1);

    expect(
      winners
    ).to.contain.oneOf([owner.address, otherAccount.address]);

    expect(
       await betwei.gameStatus(gameId)
    ).to.equal(3);
  })

  it('Revert enrolled two times users', async() => {
    let {
      betwei,
      gameId,
      owner,
      otherAccount
    } = await initContractAndGetGameId();

    // owner not enroll two times
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), owner)
    ).to.revertedWith("User cannot enroll");

    // enroll another account
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)
    ).to.emit(betwei, "EnrolledToGame");

    // fail re-enrolled
    await expect(
      enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)
    ).to.revertedWith("User cannot enroll");

  })

  it('Success withdraw winner', async() => {

    let {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      gameId,
      owner,
      otherAccount
    } = await initContractAndGetGameId();

    await enrollToGame(betwei, gameId, utils.parseEther('1'), otherAccount)

    // close game
    await betwei.connect(owner).closeGame(gameId);

    await betwei.connect(owner).startGame(gameId)

    // Send random
    // first request.
    // TODO: new version mock chainlink can generate random number for test
    //await hardhatVrfCoordinatorV2Mock.fulfillRandomWordsWithOverride(1, betwei.address, [BigNumber.from(utils.randomBytes(32))])
    let fullFillRandoms = 
       await hardhatVrfCoordinatorV2Mock.fulfillRandomWords(1, betwei.address);

    // winners 1
    let winners = await betwei.winners(gameId);

    let gameBalance = await betwei.gameBalance(gameId);
    expect(gameBalance).to.be.greaterThan(0);

    if (owner.address === winners[0]) {
      await testWithdrawGame(betwei, owner, gameId, gameBalance, otherAccount);
    } else {
      await testWithdrawGame(betwei, otherAccount, gameId, gameBalance, owner);
    }

    expect(await betwei.gameBalance(gameId)).to.be.equal(0);
  })

  /**
   * Functions
   */

  async function testWithdrawGame(betwei: Betwei, winnerAccount: any, gameId: BigNumber, gameBalance: BigNumber, anotherAccount = undefined) {

      if (anotherAccount) {
        await expect(
          betwei.connect(anotherAccount).withdrawGame(gameId)
        ).to.revertedWith('Player not winner');
      }

      let withdrawGame = await betwei.connect(winnerAccount).withdrawGame(gameId);

      await expect(
        withdrawGame
      ).to.emit(betwei, 'WithdrawFromGame')
       .withArgs(gameId, winnerAccount.address);

      await expect(withdrawGame).to.changeEtherBalance(
        winnerAccount, gameBalance
      );
  }

  async function initContractAndGetGameId(): Promise<InitCreatedGame> {
    // init 
    const {
      betwei,
      hardhatVrfCoordinatorV2Mock,
      owner,
      otherAccount
    } : Deploy = await deployBetWai();

    let {events} = await createNewGame(betwei);
    let gameId = getGameIdFromCreatedEvent(events);

    return {betwei, hardhatVrfCoordinatorV2Mock, owner, otherAccount, gameId};
  }

  async function createNewGame(betwei: Betwei) {

    // max duration (players)
    // type 0 random winner
    let tx = await betwei.createNewGame(0, 2, {value: utils.parseEther('1')});
    let { events } = await tx.wait();

    return {events, tx};

  }

  function getGameIdFromCreatedEvent(events: any) {

    let args = events!!.filter(
      (x: any) => x.event === 'NewGameCreated'
    )[0].args;

    if(!args) {
      throw new Error('nulled args in event')
    }

    let gameId : BigNumber = args[0];
    return gameId;
  }

  async function enrollToGame(betwei: Betwei, gameId: BigNumber, amount: BigNumber, account: any) {
    return betwei.connect(account)
      .enrollToGame(gameId, {value: amount})
  }
});
