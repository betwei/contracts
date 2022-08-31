// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import 'hardhat/console.sol';
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";


contract Betwei is VRFConsumerBaseV2 {
  VRFCoordinatorV2Interface COORDINATOR;

  uint64 immutable s_subscriptionId;

  // Rinkeby address and keyhash Chainlink VRF
  address immutable vrfCoordinator; // = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
  bytes32 immutable keyHash; // = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

  uint32 callbackGasLimit = 100000;

  uint16 requestConfirmations = 3;

  uint32 numWords =  2;

  //uint256[] public s_randomWords;
  //uint256 public s_requestId;

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

  mapping(address => uint256[]) games;
  mapping(uint256 => uint256) requests;

  Game[] indexedGames;

  /**
   * Events
   */
  event NewGameCreated(uint256 indexed gameId);
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
    emit NewGameCreated(newIndex);
    Game storage newGame = indexedGames.push();
    newGame.owner = msg.sender;
    newGame.duration = _duration;
    newGame.gameType = _type;
    newGame.status = GameStatus.OPEN;
    newGame.playersBalance[msg.sender] += msg.value;
    newGame.members.push(payable(address(msg.sender)));
    newGame.gameId = newIndex;
    games[msg.sender].push(newIndex);
    return newIndex;
  }

  function enrollToGame(uint256 gameId) external payable canEnroll(gameId) hasAmount gameExists(gameId) returns(bool) {
    emit EnrolledToGame(gameId, msg.sender);
    Game storage game = indexedGames[gameId];
    game.members.push(payable(address(msg.sender)));
    games[msg.sender].push(gameId);
    if (game.duration <= game.members.length) {
      game.status = GameStatus.CLOSED;
    }
    game.playersBalance[msg.sender] += msg.value;


    return true;
  }

  function usersEnrolled(uint256 gameId) external view gameExists(gameId) returns(uint256) {
    Game storage game = indexedGames[gameId];
    return game.members.length;
  }

  function closeGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) returns(bool) {
    Game storage game = indexedGames[gameId];
    if(
      game.status != GameStatus.OPEN &&
      game.status != GameStatus.CLOSED
    ) {
      revert();
    }
    game.status = GameStatus.CLOSED;

    return true;
  }

  function startGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) {
    Game storage game = indexedGames[gameId];
    require(game.status == GameStatus.CLOSED, 'The game not is closed');
    game.status = GameStatus.CALCULATING;

    // TODO multiple winner
    _calculatingWinner(gameId);

  }

  function _calculatingWinner(uint _gameId) internal  {
    Game storage game = indexedGames[_gameId];
    require(game.status == GameStatus.CALCULATING, "You aren't at that stage yet!");

    // TODO migrato to governance smartcontract
    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      1 // num words
    );

    requests[requestId] = game.gameId;

  }


  /**
   * Chainlink VRF functions
   */


  function fulfillRandomWords(
    uint256 requestId,
    uint256[] memory randomWords
  ) internal override {
    _selectWinner(requestId, randomWords);
  }

  function _selectWinner(uint256 requestId, uint256[] memory randomWords) public {
    uint256 gameIndex = requests[requestId];
    Game storage game = indexedGames[gameIndex];
    require(game.status == GameStatus.CALCULATING, "Game not exists");
    game.status = GameStatus.FINISHED;
    game.solution = randomWords[0];
    uint256 winnerIndex = game.solution % game.members.length;
    game.winners.push(game.members[winnerIndex]);
    emit FinishGame(game.gameId, game.winners);
  }

  function gameStatus(uint _gameId) public view returns(uint256) {
    return uint256(indexedGames[_gameId].status);
  }

  function winners(uint _gameId) public view returns(address[] memory) {
    return indexedGames[_gameId].winners;
  }

  function playerGames(address player) public view returns(uint256[]) {
    return games[player];
  }

  /**
   * Start - Modifiers
   */
  modifier onlyOwner() {
    require(msg.sender == s_owner);
    _;
  }

  modifier gameExists(uint256 _gameId) {
    require(indexedGames[_gameId].gameId >= 0, 'Game not exists');
    _;
  }

  modifier canEnroll(uint256 _gameId) {
    Game storage game = indexedGames[_gameId];
    require(game.playersBalance[msg.sender] <= 0, "User cannot enroll");
    require(game.duration > game.members.length, "User cannot enroll");
    require(game.status == GameStatus.OPEN, "User cannot enroll");
    _;
  }

  modifier canManageGame(uint _gameId) {
    Game storage game = indexedGames[_gameId];
    require(game.owner == msg.sender, "Can't start game");
    _;
  }

  modifier hasAmount() {
    require(msg.value > 0, "Amount has greather than 0 ");
    _;
  }

}
