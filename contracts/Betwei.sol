// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";


contract Betwei is VRFConsumerBaseV2 {
  VRFCoordinatorV2Interface COORDINATOR;

  uint64 s_subscriptionId;

  // Rinkeby address and keyhash Chainlink VRF
  address vrfCoordinator; // = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
  bytes32 keyHash; // = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

  uint32 callbackGasLimit = 100000;

  uint16 requestConfirmations = 3;

  uint32 numWords =  2;

  uint256[] public s_randomWords;
  uint256 public s_requestId;

  address s_owner;

  enum GameTypes {
    RANDOMWINNER
  }

  enum GameStatus {
    OPEN,
    CLOSED,
    CALCULATING,
    FINISHED
  }

  struct Game {
    GameType type;
    GameStatus status;
    address gameOwner;
    // TODO only registered by owner in private games?
    address payable[] players;
    uint256 gameId;
    uint256 duration;
    // TODO block number create game?
  }

  mapping(address => Game[]) games;

  Game[] indexedGames;


  constructor(
    uint64 _subscriptionId,
    bytes32 _keyHash,
    address _vrfCoordinatorAddress
  )
    VRFConsumerBaseV2(_vrfCoordinatorAddress)
  {
    COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorAddress);
    s_owner = msg.sender;
    keyHash = _keyHash;
    s_subscriptionId = _subscriptionId;
  }

  /**
   * Manage game
   */

  /**
   * Create new game
   * duration param -> max players
   * return gameId
   */
  function createNewGame(GameType _type, uint16 _duration) public returns(uint256) {
    uint256 newIndex = indexedGames.length; 
    indexedGames++;
    Game memory newGame = new Game;
    newGame.owner = msg.sender;
    newGame.durantion = _duration;
    newGame.type = _type;
    newGame.status = GameStatus.OPEN;
    newGame.players.push(msg.sender);
    newGame.gameId = newIndex;

    games[msg.sender].push(newGame)
    indexedGames.push(newGame)

    return newIndex;
  }



  /**
   * Chainlink VRF functions
   */

  // Assumes the subscription is funded sufficiently.
  function requestRandomWords() external onlyOwner {
    // Will revert if subscription is not set and funded.
    s_requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );

    // TODO emit event
  }

  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
  ) internal override {
    s_randomWords = randomWords;
  }

  modifier onlyOwner() {
    require(msg.sender == s_owner);
    _;
  }
}
