pragma solidity ^0.4.11;


import '../Ownable.sol';
import '../Token.sol';
import '../Crowdsale.sol';



contract StarkyDAO is Ownable{
  using SafeMath for uint;

  /* Contract Variables */
  StarkyToken public daoToken;
  StarkyCrowdsale public daoCrowdsale;

  uint256 public minimumQuorum;
  uint256 public marginForMajority;
  uint256 public debatingPeriod;
  Proposal[] public proposals;
  uint256 public proposalsNumber = 0;

  Withdrawal[] public withdrawals;
  uint256 public withdrawalsNumber = 0;
  uint256 withdrawalTimeWindow;
  uint256 withdrawalMaxAmount;

  bool isDissolved = false;
  uint256 dissolvedBalance;
  mapping (address => bool) accountPayouts;

  /* Contract Events */
  event ProposalAddedEvent(address indexed beneficiary, uint256 etherAmount, string description, uint256 proposalID);
  event VotedEvent(uint256 indexed proposalID, address indexed voter, bool indexed inSupport, uint256 voterTokens, string justificationText);
  event ProposalTalliedEvent(uint256 indexed proposalID, bool indexed quorum, bool indexed result);
  event ProposalExecutedEvent(uint256 indexed proposalID);
  event MoneyWithdrawn(address indexed beneficiary, uint256 amount);
  event BalanceToDissolve(uint256 amount);

  /* Contract Structures */
  enum ProposalState {Proposed, NoQuorum, Rejected, Passed, Executed}

  struct Proposal {
    /* Proposal content */
    address beneficiary;
    uint256 etherAmount;
    string description;
    bytes32 proposalHash;

    /* Proposal state */
    ProposalState state;

    /* Voting state */
    uint256 votingDeadline;
    Vote[] votes;
    uint256 votesNumber;
    mapping (address => bool) voted;
  }

  struct Vote {
    address voter;
    bool inSupport;
    uint256 voterTokens;
    string justificationText;
  }

  struct Withdrawal {
    address beneficiary;
    uint256 amount;
    uint256 time;
  }


  /**
   * @dev Constructor
   * @param _crowdsaleModerator            address Moderator of the crowdsale
   * @param _minimumQuorumInPercents       uint256 The minimum number of tokens that must participate in a vote to achieve a quorum (in percents of total supply)
   * @param _marginForMajorityInPercents   uint256 Min percent of votes in favor required to pass the proposal (in percents of total votes)
   * @param _debatingPeriodInMinutes       uint256 Min time to vote for an proposal [min]
   * @param _withdrawalTimeWindowInMinutes uint256 Size of sliding time window to check total amount of withdrawals [min]
   * @param _withdrawalMaxAmountInWei      uint256 Size of the max amount of withdrawals during the sliding time window [max]
   */
  function StarkyDAO(
    address _crowdsaleModerator,
    uint256 _minimumQuorumInPercents,
    uint256 _marginForMajorityInPercents,
    uint256 _debatingPeriodInMinutes,
    uint256 _withdrawalTimeWindowInMinutes,
    uint256 _withdrawalMaxAmountInWei
  )
    payable
  {
    daoToken = new StarkyToken();
    daoCrowdsale = new StarkyCrowdsale(this, _crowdsaleModerator, 100, 1000, 10 * 24 * 60, 5, 1, daoToken);

    /* Setup rules */
    minimumQuorum = _minimumQuorumInPercents;
    marginForMajority = _marginForMajorityInPercents;
    debatingPeriod = _debatingPeriodInMinutes * 1 minutes;
    withdrawalTimeWindow = _withdrawalTimeWindowInMinutes * 1 minutes;
    withdrawalMaxAmount = _withdrawalMaxAmountInWei * 1 wei;
  }


  /**
   * @dev Blank fallback functions to receive ETH and tokens
   */
  function() payable onlyActiveDAO {}


  /* Setters */
  /* Change Withdraw Tracking rules */
  function setWithdrawalMaxAmount(uint _withdrawalMaxAmountInWei) {
    if (msg.sender != address(this)) {
      throw;
    }
    withdrawalMaxAmount = _withdrawalMaxAmountInWei;
  }

  /* Change Voting majority required */
  function setMarginForMajority(uint _marginForMajorityInPercents) {
    if (msg.sender != address(this)) {
      throw;
    }
    marginForMajority = _marginForMajorityInPercents;
  }
  
   /* Change Voting quorum required */
  function setMinimumQuorum(uint _minimumQuorumInPercents) {
    if (msg.sender != address(this)) {
      throw;
    }
    minimumQuorum = _minimumQuorumInPercents;
  }


  /* Proposal-related functions */

  /**
   * @dev Calculate hash of an proposal
   * @param _beneficiary         address Beneficiary of proposal
   * @param _etherAmountInWei    uint256 ETH to send to the beneficiary (can be 0)
   * @param _transactionBytecode bytes   Transaction bytecode to execute
   * @return                     bytes32 Hash of the proposal
   */
  function getProposalHash(
    address _beneficiary,
    uint256 _etherAmountInWei,
    bytes _transactionBytecode
  )
    constant returns (bytes32)
  {
    return sha3(_beneficiary, _etherAmountInWei, _transactionBytecode);
  }

  /**
   * @dev Create new proposal
   * @param _beneficiary         address Beneficiary of proposal
   * @param _etherAmountInWei    uint256 ETH to send to the beneficiary
   * @param _description         string  Description of the proposal in text
   * @param _transactionBytecode bytes   Transaction bytecode to execute
   * @return                     uint256 ID of created proposal
   */
  function createProposal(
    address _beneficiary,
    uint256 _etherAmountInWei,
    string _description,
    bytes _transactionBytecode
  )
  onlyDAOMember onlyActiveDAO
  returns (uint256 proposalID)
  {
    proposalID = proposals.length;
    proposals.length += 1;
    proposalsNumber = proposalID + 1;

    proposals[proposalID].beneficiary = _beneficiary;
    proposals[proposalID].etherAmount = _etherAmountInWei;
    proposals[proposalID].description = _description;
    proposals[proposalID].proposalHash = getProposalHash(_beneficiary, _etherAmountInWei, _transactionBytecode);
    proposals[proposalID].state = ProposalState.Proposed;
    proposals[proposalID].votingDeadline = now + debatingPeriod * 1 seconds;
    proposals[proposalID].votesNumber = 0;

    ProposalAddedEvent(_beneficiary, _etherAmountInWei, _description, proposalID);

    return proposalID;
  }

  /**
   * @dev Vote for an proposal
   * @param _proposalID        address Target proposal ID
   * @param _inSupport         bool    In support or not
   * @param _justificationText string  Reasons of decision
   */
  function vote(
    uint256 _proposalID,
    bool _inSupport,
    string _justificationText
  )
    onlyDAOMember onlyActiveDAO
  {
    Proposal p = proposals[_proposalID];

    if (p.state != ProposalState.Proposed) throw;
    if (p.voted[msg.sender] == true) throw;

    var voterBalance = daoToken.balanceOf(msg.sender);
    daoToken.blockAccount(msg.sender);

    p.voted[msg.sender] = true;
    p.votes.push(Vote(msg.sender, _inSupport, voterBalance, _justificationText));
    p.votesNumber += 1;

    VotedEvent(_proposalID, msg.sender, _inSupport, voterBalance, _justificationText);
  }

  /**
   * @dev Finish voting on an proposal
   * @param _proposalID        address Target proposal ID
   */
  function finishProposalVoting(uint256 _proposalID) onlyDAOMember onlyActiveDAO {
    Proposal p = proposals[_proposalID];
    
    /* Check is voting deadline reached */
    if (now < p.votingDeadline) throw;
    if (p.state != ProposalState.Proposed) throw;

    var _votesNumber = p.votes.length;
    uint256 tokensFor = 0;
    uint256 tokensAgainst = 0;
    
    /* Count votes */
    for (uint256 i = 0; i < _votesNumber; i++) {
      if (p.votes[i].inSupport) {
        tokensFor += p.votes[i].voterTokens;
      }
      else {
        tokensAgainst += p.votes[i].voterTokens;
      }
      daoToken.unblockAccount(p.votes[i].voter);
    }
    
    /* Check if quorum is not reached */
    if ((tokensFor + tokensAgainst) < daoToken.totalSupply().mul(minimumQuorum).div(100)) {
      p.state = ProposalState.NoQuorum;
      ProposalTalliedEvent(_proposalID, false, false);
      return;
    }
    
    /* Check if majority is  not reached */
    if (tokensFor < (tokensFor + tokensAgainst).mul(marginForMajority).div(100)) {
      p.state = ProposalState.Rejected;
      ProposalTalliedEvent(_proposalID, true, false);
      return;
    }
    
    /* Else Validate */
    else {
      p.state = ProposalState.Passed;
      ProposalTalliedEvent(_proposalID, true, true);
      return;
    }
  }

  /**
   * @dev Execute passed proposal
   * @param _proposalID          address Target proposal ID
   * @param _transactionBytecode bytes   Transaction bytecode to execute
   */
  function executeProposal(uint256 _proposalID, bytes _transactionBytecode) onlyDAOMember onlyActiveDAO {
    Proposal p = proposals[_proposalID];

    if (p.state != ProposalState.Passed) throw;

    var proposalHashForCheck = getProposalHash(p.beneficiary, p.etherAmount, _transactionBytecode);
    if (p.proposalHash != proposalHashForCheck) throw;

    p.state = ProposalState.Executed;
    if (!p.beneficiary.call.value(p.etherAmount * 1 wei)(_transactionBytecode)) {
      throw;
    }

    ProposalExecutedEvent(_proposalID);
  }


  /* Withdrawals-related functions */
  /**
   * @dev Withdraw money
   * @param _amount uint256 Amount to withdraw
   */
  function withdraw(uint256 _amount) onlyOwner onlyActiveDAO {
    /* Add new record for the withdrawal */
    var withdrawalID = withdrawals.length;
    withdrawals.length += 1;
    withdrawalsNumber = withdrawalID + 1;
    
    withdrawals[withdrawalID].beneficiary = msg.sender;
    withdrawals[withdrawalID].amount = _amount;
    withdrawals[withdrawalID].time = now;

    /* Check that new withdrawal fits the limits */
    var slidingWindowStartTimestamp = now - withdrawalTimeWindow;

    uint256 withdrawalsAmount = 0;
    for (uint256 _withdrawalID = withdrawalsNumber - 1; _withdrawalID >= 0; _withdrawalID--) {
      if (withdrawals[_withdrawalID].time < slidingWindowStartTimestamp) {
        break;
      }
      withdrawalsAmount = withdrawalsAmount.add(withdrawals[_withdrawalID].amount);
    }
    if (withdrawalsAmount > withdrawalMaxAmount) {
      /* If withdrawal do not fit limits - throw and reset all changes */
      throw;
    }

    /* Withdraw */
    msg.sender.transfer(_amount);

    MoneyWithdrawn(msg.sender, _amount);
  }


  /* Dissolve contract */

  /**
   * @dev Dissolve contract. In order to dissolve someone have to create a proposal that invoke this function.
   */
  function dissolveContract() onlyActiveDAO {
    if (msg.sender != address(this)) {
      throw;
    }

    isDissolved = true;
    dissolvedBalance = address(this).balance;
    BalanceToDissolve(dissolvedBalance);
  }

  /**
   * @dev Withdraw dissolved funds. Tokens will be lost forever
   */
  function withdrawDissolvedFunds() onlyDissolvedDAO onlyDAOMember {
    if (accountPayouts[msg.sender]) {
      throw;
    }

    accountPayouts[msg.sender] = true;
    /* Block forever */
    daoToken.blockAccount(msg.sender);

    var tokenBalance = daoToken.balanceOf(msg.sender);
    var ethToSend = tokenBalance.div(daoToken.totalSupply()).mul(dissolvedBalance);
    msg.sender.transfer(ethToSend);
  }


  /* Helpers */
  /**
   * @dev Throws if sender fo not hold tokens
   */
  modifier onlyDAOMember {
    if (daoToken.balanceOf(msg.sender) <= 0) {
      throw;
    }
    _;
  }

  /**
   * @dev Throws if DAO dissolved
   */
  modifier onlyActiveDAO {
    if (isDissolved) {
      throw;
    }
    _;
  }

  /**
   * @dev Throws if DAO not dissolved
   */
  modifier onlyDissolvedDAO {
    if (isDissolved == false) {
      throw;
    }
    _;
  }
}
