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

  uint32 callbackGasLimit = 150000;

  uint16 requestConfirmations = 3;

  uint32 numWords =  1;

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
    string description;
    // TODO only registered by owner in private games?
    address payable[] members;
    // Quienes son los ganadores
    address[] winnersIndexed;

    //mapping(address => bool) winners;
    //mapping(address => uint256) playersBalance;
    uint256 balance;
    uint256 gameId;
    uint256 duration;
    uint256 solution;
    uint256 neededAmount;
    // TODO block number create game?
  }

  mapping(uint256 => mapping(address => bool)) winnersByGame;
  mapping(uint256 => mapping(address => uint256)) playerBalanceByGame;
  mapping(address => Game[]) games;
  mapping(uint256 => uint256) requests;

  Game[] indexedGames;

  /**
   * Events
   */
  event NewGameCreated(uint256 indexed gameId);
  event EnrolledToGame(uint256 indexed gameId, address indexed player);
  event FinishGame(uint256 indexed gameId); 
  event WithdrawFromGame(uint256 indexed gameId, address indexed winner);


  constructor(
    uint64 _subscriptionId,
    bytes32 _keyHash,
    address _vrfCoordinatorAddress
  )
    VRFConsumerBaseV2(_vrfCoordinatorAddress)
  {
    COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorAddress);
    s_owner = msg.sender;
    vrfCoordinator = _vrfCoordinatorAddress;
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
   * TODO: amount parameter
   */
  function createNewGame(GameType _type, uint16 _duration, string memory _description) public payable hasAmount returns(uint256) {
    uint256 newIndex = indexedGames.length; 
    emit NewGameCreated(newIndex);
    Game storage newGame = indexedGames.push();
    newGame.owner = msg.sender;
    newGame.duration = _duration;
    newGame.gameType = _type;
    newGame.status = GameStatus.OPEN;
    newGame.neededAmount = msg.value;
    playerBalanceByGame[newIndex][msg.sender] += msg.value;
    //newGame.playersBalance[msg.sender] += msg.value;
    newGame.members.push(payable(address(msg.sender)));
    newGame.gameId = newIndex;
    newGame.balance += msg.value;
    newGame.description = _description;
    //games[msg.sender].push(newIndex);
    games[msg.sender].push(newGame);
    return newIndex;
  }

  function enrollToGame(uint256 gameId) external payable canEnroll(gameId) hasAmount gameExists(gameId) returns(bool) {
    emit EnrolledToGame(gameId, msg.sender);
    Game storage game = indexedGames[gameId];
    game.members.push(payable(address(msg.sender)));
    games[msg.sender].push(game);
    if (game.duration <= game.members.length) {
      game.status = GameStatus.CLOSED;
    }
    //game.playersBalance[msg.sender] += msg.value;
    playerBalanceByGame[gameId][msg.sender] += msg.value;
    game.balance += msg.value;

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
      numWords
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
    address winnerAddress = game.members[winnerIndex];
    // only 1 winner
    game.winnersIndexed.push(winnerAddress);
    winnersByGame[gameIndex][winnerAddress] = true;
    //game.winners[winnerAddress] = true;
    emit FinishGame(game.gameId);
  }

  /**
   * Withdraw function
   */
  function withdrawGame(uint256 _gameId) external gameExists(_gameId) returns(bool) {
    Game memory game = indexedGames[_gameId];
    require(game.balance != 0, "Game finished, balance 0");
    require(game.status == GameStatus.FINISHED, "Game no finished");
    require(winnersByGame[_gameId][msg.sender], 'Player not winner');
    require(playerBalanceByGame[_gameId][msg.sender] != 0, 'Player balance 0');
    emit WithdrawFromGame(game.gameId, msg.sender);
    uint256 balanceGame = game.balance;
    game.balance = 0;
    // save game
    indexedGames[_gameId] = game;

    // transfer all game balance
    (bool success,) = payable(msg.sender).call{value: balanceGame}("");
    require(success, "Transfer amount fail");

    return true;
  }

  /**
   * Read functions
   */

  function gameStatus(uint _gameId) public view returns(uint256) {
    return uint256(indexedGames[_gameId].status);
  }

  function winners(uint _gameId) public view returns(address[] memory) {
    return indexedGames[_gameId].winnersIndexed;
  }

  function gameBalance(uint _gameId) public view returns(uint256) {
    return indexedGames[_gameId].balance;
  }

  function playerGames(address _player) external view returns(Game[] memory) {
    return games[_player];
  }

  function viewGame(uint256 _gameId)
    external
    view
    returns(
        Game memory
  ) {
    return indexedGames[_gameId];
  }

  function getBalance() public view onlyOwner returns(uint256) {
    return address(this).balance;
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
    require(playerBalanceByGame[_gameId][msg.sender] == 0, "User cannot enroll");
    Game memory game = indexedGames[_gameId];
    require(game.neededAmount <= msg.value, "The amount required should be greather or equal");
    require(game.duration > game.members.length, "User cannot enroll");
    require(game.status == GameStatus.OPEN, "User cannot enroll");
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
