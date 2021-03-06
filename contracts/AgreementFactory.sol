pragma solidity ^0.5.0;

import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

/// @Author RickGriff
/// EtherSplit dApp
contract AgreementFactory {

  address public factoryOwner;

  mapping(address => bool) public allAgreements;

  /// Map user to list of agreements they've created or joined
  mapping(address => address[]) public userToAgreements;

  /// Map user to list of agreements they've been invited to
  mapping(address => address[]) public userToInvites;

  event AgreementCreated (address from, address agreementAddr);
  event AgreementAdded (address agreementAddr, bool inAllAgreementsList);

  constructor() public {
    factoryOwner = msg.sender;
  }

  function createNewAgreement() public  {
    Agreement newAgreement = new Agreement(msg.sender);
    /// Add agreement addr to allAgreements and user's list
    address agreementAddress = address(newAgreement);
    allAgreements[agreementAddress] = true;
    userToAgreements[msg.sender].push(agreementAddress);
    emit AgreementCreated(msg.sender, agreementAddress);
    emit AgreementAdded(agreementAddress, allAgreements[agreementAddress]);
  }

  function getUsersAgreements(address _user) public view returns (address[] memory ) {
    return( userToAgreements[_user] );
  }

  function getMyAgreements() public view returns (address[] memory ) {
    return( userToAgreements[msg.sender] );
  }

  function getMyInvites() public view returns (address[] memory ) {
    return( userToInvites[msg.sender] );
  }

  /// Called by a child Agreement when a new user registers on the child.
  function newRegisteredUser(address _user) public _onlyChildContract {
    userToAgreements[_user].push(msg.sender);
  }

  /// Called by a child Agreement when a new account is invited to the child.
  function newInvite(address _friend) public _onlyChildContract {
    userToInvites[_friend].push(msg.sender);
  }

  /// Length getters and modifiers
  function getMyAgreementsCount() public view returns(uint myAgreementsCount) {
    return userToAgreements[msg.sender].length;
  }

  function getMyInvitesCount() public view returns(uint myAgreementsCount) {
    return userToInvites[msg.sender].length;
  }

  function getUsersAgreementsCount(address _user) public view returns(uint usersAgreementsCount) {
    return userToAgreements[_user].length;
  }

  modifier _onlyChildContract {
    require( allAgreements[msg.sender] == true, 'Sending contract not listed as a child of AgreementFactory');
    _;
  }
}

contract Agreement {

  using SafeMath for uint;

  address public parentFactory;
  address public parentFactoryOwner;
  address public user_1;
  address public invited_friend;
  address public user_2;
  string public user_1_name;
  string public user_2_name;

  /// The net balance of who owes who.  Positive if user_2 owes more, negative if user_1 owes more.
  int public balance;

  uint public txCounter; /// counts the number of transactions created.

  /// Map user to the list of the pending transactions.
  mapping( address => Tx[] ) public pendingTransactions;

  /** @dev It's not possible to call elements in nested arrays via web3.
  * So explicitly set a Tx array for user 1 and user 2, to allow calls from UI.
  * Assignment happens in the 'createPending' func. */
  Tx[] public pendingTransactions_1;
  Tx[] public pendingTransactions_2;

  Tx[] public confirmedTransactions;

  /// basic transaction object.
  struct Tx {
    uint amount;
    bool split;
    address creator;
    address confirmer;
    address debtor;
    string description;
    uint index;
    uint timestamp;
  }

  ///  ****** constructor and user registration functions ******
  constructor(address _creator) public {
    parentFactory = msg.sender;
    AgreementFactory factory = AgreementFactory(parentFactory);
    parentFactoryOwner = factory.factoryOwner();
    user_1 = _creator;
  }

  /// Store the user's name
  function setName(string memory _name) onlyUser public {
    if (msg.sender == user_1) {
      require(bytes(user_1_name).length == 0, "You already set your name!");
      user_1_name = _name;
    } else if (msg.sender == user_2) {
      require(bytes(user_2_name).length == 0, "You already set your name!");
      user_2_name = _name;
    }
  }

  /// Set the invited friend's address
  function inviteFriend(address _friend) onlyUser1 onlyUser2NotRegistered public {
    require(_friend != msg.sender, 'You cant invite yourself!');
    require(invited_friend == address(0), 'You have already invited someone!');
    invited_friend = _friend;
    AgreementFactory factory = AgreementFactory(parentFactory);
    factory.newInvite(_friend);
  }

  function registerUser2() onlyInvitedFriend onlyUser2NotRegistered public {
    user_2 = msg.sender;
    require(user_2 == msg.sender); /// check user_2 was set
    /// send the registration data to parent factory
    AgreementFactory factory = AgreementFactory(parentFactory);
    factory.newRegisteredUser(user_2);
  }

  /// ****** Functions for creating and confirming transactions ******

  /// Create a pending Tx, to be confirmed by the other user
  function createPending(uint _amount, bool _split, address _debtor, string  memory _description) onlyUser onlyBothRegistered public {
    require( _debtor == user_1 || _debtor == user_2, 'debtor must be a registered user' );
    require( bytes(_description).length < 35, 'Description too long' );

    uint timeNow = timeStamp();

    Tx memory newPendingTx;

    /// set the other user as confirmer
    newPendingTx.confirmer = getOtherUser(msg.sender);
    /// If Tx cost was split, set the amounted owed to half of Tx amount
    if (_split == true) {
      newPendingTx.amount = _amount/2;
    } else if(_split == false) {
      newPendingTx.amount = _amount;
    }
    /// set remaining Tx attributes
    newPendingTx.split = _split;
    newPendingTx.creator = msg.sender;
    newPendingTx.debtor = _debtor;
    newPendingTx.description = _description;
    newPendingTx.index = txCounter;
    newPendingTx.timestamp = timeNow;

    /// append new Tx to the confirmer's pending Tx array, and update Tx counter
    pendingTransactions[newPendingTx.confirmer].push(newPendingTx);
    txCounter = txCounter.add(1);

    /// Update Tx lists
    pendingTransactions_1 = pendingTransactions[user_1];
    pendingTransactions_2 = pendingTransactions[user_2];
  }

  function confirmAll() onlyUser onlyBothRegistered public {
    Tx[] storage allPendingTx = pendingTransactions[msg.sender];
    Tx[] memory memAllPendingTx = allPendingTx;  /// copy pending Txs to memory

    allPendingTx.length = 0; /// delete all pending txs in storage

    int balanceChange  = 0;
    /// Add all pending Txs to confirmed Tx list, and calculate the net change in balance
    for (uint i = 0; i < memAllPendingTx.length; i++) {
      confirmedTransactions.push(memAllPendingTx[i]);
      balanceChange = balanceChange + changeInBalance(memAllPendingTx[i]);
    }

    /// update lists and balance
    pendingTransactions_1 = pendingTransactions[user_1];
    pendingTransactions_2 = pendingTransactions[user_2];
    balance = balance + balanceChange;
  }

  function confirmSingleTx(uint _txIndex) onlyUser onlyBothRegistered public {
    Tx[] storage allPendingTx =  pendingTransactions[msg.sender];

    uint len = allPendingTx.length;
    Tx memory transaction = allPendingTx[_txIndex];  /// copy Tx to memory

    /** @dev delete transaction fron pendingTx list.
    * This approach preserves array length, but not order:
    */
    delete allPendingTx[_txIndex]; /// delete Tx, leaving empty slot
    allPendingTx[_txIndex] = allPendingTx[len - 1];  /// copy last Tx to empty slot
    delete allPendingTx[len - 1];   /// delete the last Tx
    allPendingTx.length--;  /// decrement array size by one to remove last (empty) slot

    /// Append Tx to confirmed transactions list
    confirmedTransactions.push(transaction);

    /// Update lists and balance
    pendingTransactions_1 = pendingTransactions[user_1];
    pendingTransactions_2 = pendingTransactions[user_2];
    balance = balance + changeInBalance(transaction);
  }

  /** Calculates balance from scratch from total confirmed Tx history,
  * and checks it is equal to running balance.
  */
  function balanceHealthCheck () onlyUserOrFactoryOwner public view returns (int _testBal, int _bal, bool) {
    int testBalance = 0;
    for (uint i = 0; i < confirmedTransactions.length; i++) {
      testBalance = testBalance + changeInBalance(confirmedTransactions[i]);
    }

    if (testBalance != balance) {
      return(testBalance, balance, false);
    } else if (testBalance == balance) {
      return(testBalance, balance, true);
    }
  }

  /// ****** Helper and getter functions ******

  /// Return the change to a balance caused by a purchase
  function changeInBalance(Tx memory _purchase) private view returns (int _change) {
    int change = 0;
    if (_purchase.debtor == user_1) {
      change = -int(_purchase.amount);
      return change;
    } else if (_purchase.debtor == user_2) {
      change = int(_purchase.amount);
      return change;
    }
  }

  function getOtherUser(address _user) private view returns (address) {
    require(_user == user_1 || _user == user_2, 'user must be registered');
    if (_user == user_1) {
      return user_2;
    } else if (_user == user_2) {
      return user_1;
    }
  }

  function timeStamp() private view returns (uint) {
    return block.timestamp;
  }

  /// Length getters for lists of Txs
  function getPendingTxsLength1() public view returns(uint) {
    return pendingTransactions[user_1].length;
  }

  function getPendingTxsLength2() public view returns(uint) {
    return pendingTransactions[user_2].length;
  }

  function getConfirmedTxsLength() public view returns(uint) {
    return confirmedTransactions.length;
  }

  /// ****** Modifiers *****
  modifier onlyUser {
    require(msg.sender == user_1 || msg.sender == user_2, 'Must be a registered user');
    _;
  }

  modifier onlyUserOrFactoryOwner {
    require(msg.sender == parentFactoryOwner || (msg.sender == user_1 || msg.sender == user_2), 'Must be a registered user');
    _;
  }

  modifier onlyUser1 {
    require(msg.sender == user_1, 'Must be registered user 1');
    _;
  }

  modifier onlyInvitedFriend {
    require(msg.sender == invited_friend, 'Must be the invited friend');
    _;
  }

  modifier onlyUser2NotRegistered {
    require (user_2 == address(0), 'User 2 already registered');
    _;
  }

  modifier onlyBothRegistered {
    require (user_1 != address(0) && user_2 != address(0), 'Two users must be registered');
    _;
  }
}
