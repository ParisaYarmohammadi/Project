pragma solidity ^0.4.8;


import "./StandardToken.sol";
import '../Ownable.sol';


/**
 * @title BlockableToken
 *
 * @dev Simple ERC20 Token example, with blocking (for example, for voting in a DAO contract)
 */
contract BlockableToken is StandardToken, Ownable {

  mapping (address => uint) accountBlocks;

  /**
   * @dev Block account
   * @param _account address Account ot block
   */
  function blockAccount(address _account) onlyOwner {
    var _accountBlocks = accountBlocks[_account];
    accountBlocks[_account] = _accountBlocks.add(1);
  }

  /**
   * @dev Unblock account
   * @param _account address Account ot unblock
   */
  function unblockAccount(address _account) onlyOwner {
    var _accountBlocks = accountBlocks[_account];
    accountBlocks[_account] = _accountBlocks.sub(1);
  }

  /**
   * @dev Unblock account
   * @param _account address Account ot unblock
   */
  function isBlocked(address _account) constant returns (bool result) {
    return (accountBlocks[_account] > 0);
  }

  function transfer(address _to, uint _value) onlyNotBlocked(msg.sender) {
    return super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) onlyNotBlocked(_from) {
    return super.transferFrom(_from, _to, _value);
  }

  /**
   * @dev Throws if tokens of _from blocked
   * @param _from address The address which you want to send tokens from
   */
  modifier onlyNotBlocked(address _from) {
    if (accountBlocks[_from] > 0) {
      throw;
    }
    _;
  }
}
