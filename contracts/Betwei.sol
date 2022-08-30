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

  enum GameType {
    RANDOMWINNER
  }

  enum GameStatus {
    OPEN,
    CLOSED,
    CALCULATING,
    FINISHED
  }

  struct Game {
    GameType gameType;
    GameStatus status;
    address owner;
    // TODO only registered by owner in private games?
    address payable[] members;
    address[] winners;
    mapping(address => uint256) playersBalance;
    uint256 gameId;
    uint256 duration;
    uint256 solution;
    // TODO block number create game?
  }

  mapping(address => Game[]) games;
  mapping(uint256 => Game[]) requests;

  Game[] indexedGames;

  /**
   * Events
   */
  event EnrolledToGame(uint256 gameId, address indexed player);
  event FinishGame(uint256 gameId, address[] indexed winner); // TODO multiples winners?


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
  function createNewGame(GameType _type, uint16 _duration) public payable hasAmount returns(uint256) {
    uint256 newIndex = indexedGames.length; 

    Game storage newGame;
    newGame.owner = msg.sender;
    newGame.duration = _duration;
    newGame.gameType = _type;
    newGame.status = GameStatus.OPEN;
    newGame.playersBalance[msg.sender] += msg.value;
    newGame.members.push(msg.sender);
    newGame.gameId = newIndex;

    games[msg.sender].push(newGame);
    indexedGames[newIndex] = newGame;

    return newIndex;
  }

  function enrollToGame(uint256 gameId) external gameExists(gameId) canEnroll(gameId) hasAmount returns(bool) {
    emit EnrolledToGame(gameId, msg.sender);
    Game memory game = indexedGames[gameId];
    game.members.push(msg.sender);
    if (game.durantion <= game.members.length) {
      game.status = GameStatus.CLOSED;
    }
    game.playersBalance[msg.sender] += msg.value;


    return true;
  }

  function usersEnrolled(uint256 gameId) external view gameExists(gameId) returns(bool) {
    Game memory game = indexedGames[gameId];
    return game.members.length;
  }

  function closeGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) returns(bool) {
    Game memory game = indexedGames[gameId];
    require(game.status == GameStatus.OPEN);
    game.status = GameStatus.CLOSED;

    return true;
  }

  function startGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) {
    Game memory game = indexedGames[gameId];
    require(game.status == GameStatus.CLOSED);
    game.status = GameStatus.CALCULATING;

    // TODO multiple winner
    _calculatingWinner(gameId);

  }

  function _calculatingWinner(uint _gameId) internal  {
    Game memory game = indexedGames[_gameId];
    require(game.status == GameStatus.CALCULATING, "You aren't at that stage yet!");

    // TODO migrato to governance smartcontract
    game.status = GameStatus.FINISHED;
    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      1 // num words
    );

    requests[requestId] = game;

    //uint256 winnerIndex = randomWords[0] % game.members.length;

    //return game.members[winnerIndex];
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
    uint256 requestId,
    uint256[] memory randomWords
  ) internal override {
    Game memory game = requests[requestId];

    game.solution = randomWords[0];

    _selectWinner(game);

    //game.winners[0].call{}()
  }

  function _selectWinner(Game memory game) internal {
    emit FinishGame(game.gameId, game.winners);
    uint256 winnerIndex = game.solution % game.members.length;
    game.winners[0] =  game.members[winnerIndex];
  }



  /**
   * Start - Modifiers
   */
  modifier onlyOwner() {
    require(msg.sender == s_owner);
    _;
  }

  modifier gameExists(uint256 _gameId) {
    require(indexedGames[_gameId], 'Game not exists');
    _;
  }

  modifier canEnroll(uint256 _gameId) {
    Game memory game = indexedGames[_gameId];
    require(game.playersBalance[msg.sender] <= 0, "User cannot enroll");
    require(game.durantion > game.members.length, "User cannot enroll");
    require(game.status != GameStatus.OPEN, "User cannot enroll");
    _;
  }

  modifier canManageGame(uint _gameId) {
    Game memory game = indexedGames[_gameId];
    require(game.owner == msg.sender, "Can't start game");
    _;
  }

  modifier hasAmount() {
    require(msg.value > 0, "Amount has greather than 0 ");
    _;
  }

}
