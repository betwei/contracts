// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import 'hardhat/console.sol';
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


contract Betwei is VRFConsumerBaseV2 {
  using Strings for uint256;
  VRFCoordinatorV2Interface COORDINATOR;

  uint64 immutable s_subscriptionId;

  // @notice Rinkeby address and keyhash Chainlink VRF
  address immutable vrfCoordinator; // = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
  bytes32 immutable keyHash; // = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

  uint32 callbackGasLimit = 150000;

  uint16 requestConfirmations = 3;

  uint32 numWords =  1;

  //uint256[] public s_randomWords;
  //uint256 public s_requestId;

  address s_owner;

  enum GameType {
    RANDOMWINNER,
    RANDOM_NFT_WINNER
  }

  enum GameStatus {
    OPEN,
    CLOSED,
    CALCULATING,
    FINISHED
  }

  struct NFTGameRandom {
      IERC721 nftContract;
      uint256 tokenId;
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
  mapping(address => string[]) games;
  mapping(uint256 => uint256) requests;
  mapping(uint256 => NFTGameRandom) nftGame;

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

  // @notice Create new game, raffle a winner
  // @dev create a new Game, the type of the game is 0 (RANDOMWINNER).
  // @param _duration max players
  // @param _description description for humans
  // @return uint256
  function createSimpleNewGame(uint256 _duration, string memory _description) public payable hasAmount returns(uint256) {
      return _createNewGame(GameType.RANDOMWINNER, _duration, _description);
  }

  // @notice Create new game, draw a NFT
  // @notice Require approve transferFrom for this Betwei address
  // @dev create a new Game, the type of the game is 1 (RANDOM_NFT_WINNER).
  // @param _nftContract external contract address ERC721
  // @param _tokenId token id into ERC721 contract
  // @param _duration max players
  // @param _description description for humans
  // @return uint256
  function createRandomNFTGame(IERC721 _nftContract, uint256 _tokenId, uint256 _duration, string memory _description) public returns(uint256 _gameId) {
    NFTGameRandom memory newNft = NFTGameRandom(_nftContract, _tokenId);
    _gameId = _createNewGame(GameType.RANDOM_NFT_WINNER, _duration, _description);
    nftGame[_gameId] = newNft;
  }

  // @dev internal function to create a new game.
  // @param _type Type of game
  // @param _duration Max players
  // @param _description User description for the game
  // @returns uint256 Id the game
  function _createNewGame(GameType _type, uint256 _duration, string memory _description) internal returns (uint256) {
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
    games[msg.sender].push(
        string(abi.encodePacked(newIndex.toString(), '-', newGame.description))
    );
    return newIndex;
  }

  // @notice enroll to the game gameId
  // @dev only require neededAmount for RANDOMWINNER GameType
  // @param gameId
  // @return bool
  function enrollToGame(uint256 gameId)
    external
    payable
    canEnroll(gameId)
    gameExists(gameId)
    returns(bool)
  {
    Game storage game = indexedGames[gameId];
    require(game.gameType == GameType.RANDOM_NFT_WINNER || game.neededAmount <= msg.value, "The amount required should be greather or equal");
    emit EnrolledToGame(gameId, msg.sender);
    // add member to the game
    game.members.push(payable(address(msg.sender)));
    // add human readable description for the site
    games[msg.sender].push(
        string(abi.encodePacked(gameId.toString(), '-', game.description))
    );
    // max players? close the game
    if (game.duration <= game.members.length) {
      game.status = GameStatus.CLOSED;
    }
    // add amount to player balance and game balance
    playerBalanceByGame[gameId][msg.sender] += msg.value;
    game.balance += msg.value;

    return true;
  }

  // @notice coun users enrolled to game
  // @param gameId
  function usersEnrolled(uint256 gameId) external view gameExists(gameId) returns(uint256) {
    Game storage game = indexedGames[gameId];
    return game.members.length;
  }

  // @notice close enroll
  function closeGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) returns(bool) {
    Game memory game = indexedGames[gameId];
    if(
      game.status != GameStatus.OPEN &&
      game.status != GameStatus.CLOSED
    ) {
      revert();
    }
    game.status = GameStatus.CLOSED;
    indexedGames[gameId] = game;

    return true;
  }

  // @notice start the game and wait for calculate winner
  function startGame(uint256 gameId) external gameExists(gameId) canManageGame(gameId) {
    Game storage game = indexedGames[gameId];
    require(game.status == GameStatus.CLOSED, 'The game not is closed');
    game.status = GameStatus.CALCULATING;

    // TODO multiple winner
    _calculatingWinner(game);

  }

  // @dev send request to Chainlink VRF
  function _calculatingWinner(Game memory game) internal  {
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

  function _selectWinner(uint256 requestId, uint256[] memory randomWords) internal {
    // get game id
    uint256 gameIndex = requests[requestId];
    // get game
    Game storage game = indexedGames[gameIndex];
    require(game.status == GameStatus.CALCULATING, "Game no have status Calculating");
    emit FinishGame(game.gameId);
    // set new status and random solution
    game.status = GameStatus.FINISHED;
    game.solution = randomWords[0];
    // calculate winner
    uint256 winnerIndex = game.solution % game.members.length;
    address winnerAddress = game.members[winnerIndex];
    // temporal: only 1 winner
    game.winnersIndexed.push(winnerAddress);
    winnersByGame[gameIndex][winnerAddress] = true;
  }

  // @notice withdraw award. in the case RANDOM_NFT_WINNER, transfer owner token
  function withdrawGame(uint256 _gameId) external gameExists(_gameId) returns(bool) {
    Game memory game = indexedGames[_gameId];
    require(game.status == GameStatus.FINISHED, "Game no finished");
    require(winnersByGame[_gameId][msg.sender], 'Player not winner');
    require(
        game.gameType == GameType.RANDOM_NFT_WINNER || (game.balance != 0 && playerBalanceByGame[_gameId][msg.sender] != 0),
        "Game finished, balance 0"
    );
    emit WithdrawFromGame(game.gameId, msg.sender);
    uint256 balanceGame = game.balance;
    game.balance = 0;
    // save game
    indexedGames[_gameId] = game;

    if (game.gameType == GameType.RANDOMWINNER) {
        // transfer all game balance
        (bool success,) = payable(msg.sender).call{value: balanceGame}("");
        require(success, "Transfer amount fail");

        return true;
    }

    if (game.gameType == GameType.RANDOM_NFT_WINNER) {
        NFTGameRandom memory _nftGame = nftGame[_gameId];
        IERC721 _nftContract = _nftGame.nftContract;
        // transfer from owner game to winner
        _nftContract.transferFrom(game.owner, msg.sender, _nftGame.tokenId);
        return true;
    }

    revert('Game not implemented');
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

  function playerGames(address _player) external view returns(string[] memory) {
      return games[_player];
  }

  // @notice get game info
  function viewGame(uint256 _gameId)
    external
    view
    returns(
        Game memory
  ) {
    return indexedGames[_gameId];
  }

  function nftInfo(uint256 _gameId) external view returns(NFTGameRandom memory) {
      Game memory game = indexedGames[_gameId];
      require(game.gameType == GameType.RANDOM_NFT_WINNER, 'Game invalid type');

      return nftGame[_gameId];
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

  receive() external payable {

  }

}
