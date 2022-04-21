
pragma solidity ^0.4.8;


import '../SafeMath.sol';
import "../Token.sol";


contract Crowdsale {
  using SafeMath for uint256;
  
  /* Contract Variables */
  address public beneficiary;
  address public moderator;
  uint256 public softCap;
  uint256 public hardCap;
  uint256 public deadline;
  
  Token public tokenReward;
  uint256 public tokenPriceNumerator;
  uint256 public tokenPriceDenominator;
  string  public description;
  uint256 public amountRaised;
  mapping (address => uint256) public balanceOf;
  CrowdsaleState public crowdsaleState = CrowdsaleState.Running;

  /* Contract Structures */
  enum CrowdsaleState {
    Running,
    Success,
    Failed,
    Forwarded
  }
  
   /* Contract Events */
  event FundsReceived(address indexed backer, uint256 amount);
  event FundsWithdrawn(address indexed backer, uint256 amount);
  event CrowdsaleSuccessful(bool isSuccess);
  event CrowdsaleFundsForwarded(address indexed beneficiary);


  /**
   * @dev Creates tokens and send to the specified address.
   * @dev Token price: If want to give 5 tokens for 1 ETH - numerator 5, denominator 1
   * @dev Token price: If want to give 0.1 tokens for 1 ETH - numerator 1, denominator 10
   * @param _crowdsaleBeneficiary  address The beneficiary of crowdsale
   * @param _crowdsaleModerator    address The moderator of crowdsale
   * @param _softCapInEthers       uint256 The target amount of ETh for the crowdsale
   * @param _hardCapInEthers       uint256 The maximum amount of ETh for the crowdsale
   * @param _durationInMinutes     uint256 Maximum duration of the crowdsale
   * @param _tokenPriceNumerator   uint256 Numerator of the token price
   * @param _tokenPriceDenominator uint256 Denominator of the token price
   * @param _tokenRewardAddress    address Token used for reward
   * @param _description           string description of project
   */
  function StarkyCrowdsale (
    address _crowdsaleBeneficiary,
    address _crowdsaleModerator,
    uint256 _softCapInEthers,
    uint256 _hardCapInEthers,
    uint256 _durationInMinutes,
    uint256 _tokenPriceNumerator,
    uint256 _tokenPriceDenominator,
    address _tokenRewardAddress,
    string  _description
  ) {
    beneficiary = _crowdsaleBeneficiary;
    moderator = _crowdsaleModerator;
    fundingGoal = _softCapInEthers * 1 ether;
    fundingCap = _hardCapInEthers * 1 ether;
    deadline = now + _durationInMinutes * 1 minutes;
    tokenPriceNumerator = _tokenPriceNumerator;
    tokenPriceDenominator = _tokenPriceDenominator;
    tokenReward = Token(_tokenRewardAddress);
  }

  /* Contribution Function */
  /**
   * @dev Receive ETH and mint corresponding amount of tokens
   */
  function contribution() payable onlyRunningCrowdsale {
    var amountEth = msg.value;
    var amountToken = amountEth.mul(tokenPriceNumerator).div(tokenPriceDenominator);
    var investedFunds = balanceOf[msg.sender];

    balanceOf[msg.sender] = investedFunds.add(amountEth);
    amountRaised = amountRaised.add(amountEth);
    tokenReward.mint(msg.sender, amountToken);

    FundsReceived(msg.sender, amountEth);
  }

  /* Check if conditions are reached at the dedaline of the fundraising */
  /**
   * @dev Finish the crowdsale
   */
  function finishCrowdsale() onlyRunningCrowdsale {
    if (now < deadline && amountRaised < softCap) {
      throw;
    }
    else if (now >= deadline && amountRaised < softCap) {
      crowdsaleState = CrowdsaleState.Failed;
      tokenReward.finishMinting();
      CrowdsaleSuccessful(false);
    }
    else if (msg.sender == moderator && amountRaised >= softCap) {
      crowdsaleState = CrowdsaleState.Success;
      tokenReward.finishMinting();
      CrowdsaleSuccessful(true);
    }
    else if (amountRaised >= hardCap) {
      crowdsaleState = CrowdsaleState.Success;
      tokenReward.finishMinting();
      CrowdsaleSuccessful(true);
    }
    else {
      throw;
    }
}


  /* Refund contributions if the fundraising failed */
  /**
   * @dev Withdraw ETH back in case of failed crowdsale
   */
  function withdraw() onlyFailedCrowdsale {
    var amountEth = balanceOf[msg.sender];
    balanceOf[msg.sender] = 0;
    if (amountEth > 0) {
      msg.sender.transfer(amountEth);
      FundsWithdrawn(msg.sender, amountEth);
    }
  }

  /* Forward funds to the DAO if the fundraising is successful */
  /**
   * @dev Forward collected ETH to the crowdsale beneficiary
   */
  function forwardCrowdsaleFunding() onlySuccessfulCrowdsale onlyCrowdsaleModerator {
    crowdsaleState = CrowdsaleState.Forwarded;
    beneficiary.transfer(amountRaised);
    tokenReward.transferOwnership(beneficiary);
    CrowdsaleFundsForwarded(beneficiary);
  }

  /* Helpers */
  /**
   * @dev Throws if funding goal not reached
   */
  modifier onlyCrowdsaleModerator() {
    if (msg.sender != moderator) {
      throw;
    }
    _;
  }

  /**
   * @dev Passes if crowdsale is successful
   */
  modifier onlyRunningCrowdsale() {
    if (crowdsaleState != CrowdsaleState.Running) {
      throw;
    }
    _;
  }

  /**
   * @dev Passes if crowdsale is successful
   */
  modifier onlySuccessfulCrowdsale() {
    if (crowdsaleState != CrowdsaleState.Success) {
      throw;
    }
    _;
  }

  /**
   * @dev Passes if crowdsale is failed
   */
  modifier onlyFailedCrowdsale() {
    if (crowdsaleState != CrowdsaleState.Failed) {
      throw;
    }
    _;
  }
}
