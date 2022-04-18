pragma solidity ^0.4.8;


import "./StandardToken.sol";
import '../Ownable.sol';


contract BlockableToken is StandardToken, Ownable {

  mapping (address => uint) accountBlocks;

  function blockAccount(address _account) onlyOwner {
    var _accountBlocks = accountBlocks[_account];
    accountBlocks[_account] = _accountBlocks.add(1);
  }

  function unblockAccount(address _account) onlyOwner {
    var _accountBlocks = accountBlocks[_account];
    accountBlocks[_account] = _accountBlocks.sub(1);
  }

  function isBlocked(address _account) constant returns (bool result) {
    return (accountBlocks[_account] > 0);
  }

  function transfer(address _to, uint _value) onlyNotBlocked(msg.sender) {
    return super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) onlyNotBlocked(_from) {
    return super.transferFrom(_from, _to, _value);
  }

    modifier onlyNotBlocked(address _from) {
    if (accountBlocks[_from] > 0) {
      throw;
    }
    _;
  }
}
