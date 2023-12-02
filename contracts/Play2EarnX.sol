//SPDX-License-Identifier:MIT
pragma solidity >=0.7.0 <0.9.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract PlayToEarnX is Ownable, ReentrancyGuard {
  using Counters for Counters.Counter;
  using SafeMath for uint256;

  Counters.Counter private _totalGames;
  Counters.Counter private _totalPlayers;

  struct GameStruct {
    uint256 id;
    string title;
    string description;
    address owner;
    uint256 participants;
    uint256 numberOfWinners;
    uint256 plays;
    uint256 acceptees;
    uint256 stake;
    uint256 startDate;
    uint256 endDate;
    uint256 timestamp;
    bool deleted;
    bool paidOut;
  }

  struct PlayerStruct {
    uint id;
    uint gameId;
    address acount;
  }

  struct InvitationStruct {
    uint256 gameId;
    address account;
    bool responded;
    bool accepted;
    uint256 stake;
  }

  struct ScoreStruct {
    uint gameId;
    address player;
    uint score;
    uint prize;
    bool played;
  }

  uint256 private totalBalance;
  uint256 private servicePct;

  mapping(uint => bool) gameExists;
  mapping(uint256 => GameStruct) games;
  mapping(uint256 => PlayerStruct) players;
  mapping(uint256 => ScoreStruct[]) scores;
  mapping(uint256 => mapping(address => bool)) isListed;
  mapping(uint256 => InvitationStruct[]) invitationsOf;

  constructor(uint256 _pct) {
    servicePct = _pct;
  }

  function createGame(
    string memory title,
    string memory description,
    uint256 participants,
    uint256 numberOfWinners,
    uint256 startDate,
    uint256 endDate
  ) public payable {
    require(msg.value > 0 ether, 'Stake must be greater than zero');
    require(participants > 1, 'Partiticpants must be greater than one');
    require(bytes(title).length > 0, 'Title cannot be empty');
    require(bytes(description).length > 0, 'Description cannot be empty');
    require(startDate > 0, 'Start date must be greater than zero');
    require(endDate > startDate, 'End date must be greater than start date');
    require(numberOfWinners > 0, 'Number Of winners cannot be zero');

    _totalGames.increment();
    GameStruct memory game;

    game.id = _totalGames.current();
    game.title = title;
    game.description = description;
    game.participants = participants;
    game.numberOfWinners = numberOfWinners;
    game.startDate = startDate;
    game.endDate = endDate;
    game.stake = msg.value;
    game.timestamp = currentTime();

    games[game.id] = game;
    gameExists[game.id] = true;
    require(playedSaved(game.id), 'Failed to create player');
  }

  function deleteGame(uint256 gameId) public {
    require(gameExists[gameId], 'Game not found');
    require(games[gameId].owner == msg.sender, 'Unauthorized entity');
    games[gameId].deleted = true;
  }

  function playedSaved(uint256 gameId) internal returns (bool) {
    _totalPlayers.increment();

    PlayerStruct memory player;
    player.id = _totalPlayers.current();
    player.gameId = gameId;
    player.acount = msg.sender;

    players[player.id] = player;

    isListed[player.gameId][msg.sender] = true;

    games[player.gameId].acceptees++;
    totalBalance += msg.value;
    return true;
  }

  function invitePlayer(address account, uint256 gameId) public {
    require(gameExists[gameId], 'Game not found');
    require(games[gameId].acceptees <= games[gameId].participants, 'Out of capacity');
    require(!isListed[gameId][account], 'Player is already in this game');

    InvitationStruct memory invitation;
    invitation.gameId = gameId;
    invitation.account = account;
    invitation.stake = games[gameId].stake;

    invitationsOf[gameId].push(invitation);
  }

  function acceptInvitation(uint256 gameId, uint256 index) public payable {
    require(gameExists[gameId], 'Game not found');
    require(msg.value >= games[gameId].stake, 'Insuffcient funds');
    require(invitationsOf[gameId][index].account == msg.sender, 'Unauthorized entity');

    require(playedSaved(gameId), 'Failed to create player');

    invitationsOf[gameId][index].responded = true;
    invitationsOf[gameId][index].accepted = true;

    ScoreStruct memory score;
    score.gameId = gameId;
    score.player = msg.sender;
    scores[gameId].push(score);
  }

  function rejectInvitation(uint256 gameId, uint256 index) public {
    require(gameExists[gameId], 'Game not found');
    require(invitationsOf[gameId][index].account == msg.sender, 'Unauthorized entity');

    invitationsOf[gameId][index].responded = true;
  }

  function payout(uint256 gameId) public {
    require(gameExists[gameId], 'Game does not exist');
    require(currentTime() > games[gameId].endDate, 'Game still in session'); // disable on testing
    require(!games[gameId].paidOut, 'Game already paid out');

    uint256 fee = (games[gameId].stake.mul(servicePct)).div(100);
    uint256 profit = games[gameId].stake.sub(fee);
    payTo(owner(), fee);

    profit = profit.sub(fee.div(2));
    payTo(games[gameId].owner, fee.div(2));

    ScoreStruct[] memory Scores = new ScoreStruct[](scores[gameId].length);
    Scores = sortScores(Scores);

    for (uint i = 0; i < games[gameId].numberOfWinners; i++) {
      uint payoutAmount = profit.div(games[gameId].numberOfWinners);
      payTo(Scores[i].player, payoutAmount);
    }
    games[gameId].paidOut = true;
  }

  function sortScores(ScoreStruct[] memory scoreSheet) public pure returns (ScoreStruct[] memory) {
    uint256 n = scoreSheet.length;

    for (uint256 i = 0; i < n - 1; i++) {
      for (uint256 j = 0; j < n - i - 1; j++) {
        // Check if the players played before comparing their scores
        if (scoreSheet[j].played && scoreSheet[j + 1].played) {
          if (scoreSheet[j].score > scoreSheet[j + 1].score) {
            // Swap the elements
            ScoreStruct memory temp = scoreSheet[j];
            scoreSheet[j] = scoreSheet[j + 1];
            scoreSheet[j + 1] = temp;
          }
        } else if (!scoreSheet[j].played && scoreSheet[j + 1].played) {
          // Sort players who didn't play below players who played
          // Swap the elements
          ScoreStruct memory temp = scoreSheet[j];
          scoreSheet[j] = scoreSheet[j + 1];
          scoreSheet[j + 1] = temp;
        }
      }
    }

    return scoreSheet;
  }

  function saveScore(uint256 gameId, uint256 index, uint256 score) public {
    require(games[gameId].numberOfWinners + 1 == games[gameId].acceptees, 'Not enough players yet');
    require(scores[gameId][index].gameId == gameId, 'Player not found');
    require(!scores[gameId][index].played, 'Player already recorded');
    require(
      currentTime() >= games[gameId].startDate && currentTime() < games[gameId].endDate,
      'Game play must be in session'
    );

    games[gameId].plays++;
    scores[gameId][index].score = score;
    scores[gameId][index].played = true;
    scores[gameId][index].player = msg.sender;
  }

  function setFeePercent(uint256 _pct) public onlyOwner {
    require(_pct > 0 && _pct <= 100, 'Fee percent must be in the range of (1 - 100)');
    servicePct = _pct;
  }

  function getGames() public view returns (GameStruct[] memory Games) {
    uint256 available;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && !games[i].paidOut) {
        available++;
      }
    }

    Games = new GameStruct[](available);
    uint256 index;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && !games[i].paidOut) {
        Games[index++] = games[i];
      }
    }
  }

  function getPaidOutGames() public view returns (GameStruct[] memory Games) {
    uint256 available;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && games[i].paidOut) {
        available++;
      }
    }

    Games = new GameStruct[](available);
    uint256 index;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && games[i].paidOut) {
        Games[index++] = games[i];
      }
    }
  }

  function getMyGames() public view returns (GameStruct[] memory Games) {
    uint256 available;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && games[i].owner == msg.sender) {
        available++;
      }
    }

    Games = new GameStruct[](available);
    uint256 index;

    for (uint256 i = 1; i <= _totalGames.current(); i++) {
      if (!games[i].deleted && games[i].owner == msg.sender) {
        Games[index++] = games[i];
      }
    }
  }

  function getGame(uint256 id) public view returns (GameStruct memory) {
    return games[id];
  }

  function getInvitations(uint256 gameId) public view returns (InvitationStruct[] memory) {
    return invitationsOf[gameId];
  }

  function getScores(uint256 gameId) public view returns (ScoreStruct[] memory) {
    return scores[gameId];
  }

  function payTo(address to, uint256 amount) internal {
    (bool success, ) = payable(to).call{ value: amount }('');
    require(success);
  }

  function currentTime() internal view returns (uint256) {
    return (block.timestamp * 1000) + 1000;
  }
}