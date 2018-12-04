pragma solidity ^0.4.24;

// TODO sort out tabs lol

contract Agreement {
  address public user_1;
  address public invited_friend;
  address public user_2;

  int public balance;  // the net balance of who owes who.  Positive if user_2 owes more, negative if user_1 owes more.

  uint public txCounter; // counts the number of purchases created.

  // initialize uint lengths of transaction arrays. Useful because public variables have automatic getters, so we
  // can easily grab array lengths for testing and healthchecks.
  uint public pendingTxs1Length;
  uint public pendingTxs2Length;
  uint public confirmedTxsLength;

  Tx[] public pendingTransactions_1;  // pending transactions to be confirmed by user 1
  Tx[] public pendingTransactions_2;  // pending transactions to be confirmed by user 2
  Tx[] public confirmedTransactions;  // All Transactions approved by users

  // the basic transaction object
  struct Tx {
    uint amount;
    bool split;
    address creator;
    address confirmer;
    address debtor;
    string description;
    uint index;  // useful for tracking transactions, since they can move from a 'pending' array to 'confirmed' array.
    uint timestamp;
  }

  //  ***** constructor and user registration functions *****

  constructor() public {
    user_1 = msg.sender;
  }

  function inviteFriend(address _friend) onlyUser1 onlyUser2NotRegistered public {
    //user_1 can re-set invited_friend address, until a second user registers.  After that, this func reverts.
    invited_friend = _friend;
  }

  function registerUser2() onlyInvitedFriend onlyUser2NotRegistered public {
    user_2 = msg.sender;
  }

  // ****** Functions for creating and confirming transactions

  function createPending(uint _amount, bool _split, address _debtor, string _description) onlyUser onlyBothRegistered public {
    require( _debtor == user_1 || _debtor == user_2, 'debtor must be a registered user' );
    require( bytes(_description).length < 35, 'Description too long' );   // string length isn't always *exactly* bytes length - but this nevertheless enforces a short description.

    // create new pending tx
    Tx memory newPendingTx;

    // set the other user as confirmer
    newPendingTx.confirmer = getOtherUser(msg.sender);

    uint timeNow = timeStamp();

    // set remaining attributes
    newPendingTx.amount = _amount;
    newPendingTx.split = _split;
    newPendingTx.creator = msg.sender;
    newPendingTx.debtor = _debtor;
    newPendingTx.description = _description;
    newPendingTx.index = txCounter;
    newPendingTx.timestamp = timeNow;

    // append new tx to the confirmer's pending tx array, and updated it's length
    if (newPendingTx.confirmer == user_1) {
      pendingTransactions_1.push(newPendingTx);
      pendingTxs1Length = getPendingTxsLength1();

      } else if (newPendingTx.confirmer == user_2) {
        pendingTransactions_2.push(newPendingTx);
        pendingTxs2Length = getPendingTxsLength2();
      }

      txCounter = txCounter + 1;  // update tx counter
    }

    function confirmAll() onlyUser onlyBothRegistered public {
      Tx[] storage allPendingTx = getPendingTx(msg.sender);

      Tx[] memory memAllPendingTx = allPendingTx;  // copy pending txs to memory

      allPendingTx.length = 0; // delete all elements in pending tx array
      pendingTxs1Length = getPendingTxsLength1();  //update stored lengths of pending tx arrays
      pendingTxs2Length = getPendingTxsLength2();
      int balanceChange  = 0;

      for (uint i = 0; i < memAllPendingTx.length; i++) {
        confirmedTransactions.push(memAllPendingTx[i]);  // add Tx to confirmed array
        balanceChange = balanceChange + changeInBalance(memAllPendingTx[i]); // add the transaction amount to the balance change */
      }
      confirmedTxsLength = getConfirmedTxsLength();
      balance = balance + balanceChange;  // update the balance in storage
    }

    function confirmSingleTx(uint _txIndex) onlyUser onlyBothRegistered public {
      Tx[] storage allPendingTx = getPendingTx(msg.sender);

      uint len = allPendingTx.length;
      Tx memory transaction = allPendingTx[_txIndex];  // copy tx to memory

      // delete transaction fron pendingTx. This approach preserves array length, but not order
      delete allPendingTx[_txIndex];
      allPendingTx[_txIndex] = allPendingTx[len - 1];   // copy last element to empty slot
      delete allPendingTx[len - 1];   // delete last element
      allPendingTx.length--;  // decrement size of array by 1

      // append Tx to confirmed transactions
      confirmedTransactions.push(transaction);

      //update stored lengths
      pendingTxs1Length = getPendingTxsLength1();
      pendingTxs2Length = getPendingTxsLength2();
      confirmedTxsLength = getConfirmedTxsLength();

      balance = balance + changeInBalance(transaction);
    }

    function balanceHealthCheck () onlyUser public view returns (int _testBal, int _bal, bool) {
      // calculates balance from total confirmed tx history.  Checks == to running balance.
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

      // ***** Helper and getter functions *****
      function changeInBalance(Tx _purchase) private view returns (int _change) {
        // returns the change to a balance caused by a purchase
        int change = 0;
        if (_purchase.split == true) {
          return change;  // no overall change to balance when an expense is split
          } else if (_purchase.debtor == user_1) {
            change = -int(_purchase.amount);
            return change;
            } else if (_purchase.debtor == user_2) {
              change = int(_purchase.amount);
              return change;
            }
          }

          function getPendingTx( address _user) private view returns (Tx[] storage){
            // return the user's pending transactions list
            Tx[] storage allPendingTx;
            if (_user == user_1) {
              allPendingTx = pendingTransactions_1;
              } else if (_user == user_2) {
                allPendingTx = pendingTransactions_2;
              }
              return allPendingTx;
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

              // Length getters for lists of confirmed & pending txs
              function getPendingTxsLength1() internal view returns(uint) {
                return pendingTransactions_1.length;
              }

              function getPendingTxsLength2() internal view returns(uint) {
                return pendingTransactions_2.length;
              }

              function getConfirmedTxsLength() internal view returns(uint) {
                return confirmedTransactions.length;
              }

              /* function pendingTransactions2Length() onlyUser external view returns (uint) {
              return pendingTransactions_2.length;
              } */

              /* function pendingTransactions1Length() onlyUser external view returns (uint) {
              return pendingTransactions_1.length;
            }

            function confirmedTransactionsLength() onlyUser external view returns (uint) {
            return confirmedTransactions.length;
            } */

            // ******** Modifiers *********
            modifier onlyUser {
              require(msg.sender == user_1 || msg.sender == user_2, 'Must be a registered user');
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
