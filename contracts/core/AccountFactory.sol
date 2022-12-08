// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../credit/CreditAccount.sol";
import "../interfaces/ICreditAccount.sol";

contract AccountFactory is Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public masterCreditAccount;
    address public creditManager;
    EnumerableSet.AddressSet private creditAccountsSet;

    address public head;
    address public tail;
    mapping(address => address) private _nextCreditAccount;

    event NewCreditAccount(address indexed account);
    event InitializeCreditAccount(
        address indexed account,
        address indexed creditManager
    );
    event ReturnCreditAccount(address indexed account);

    modifier creditManagerOnly() {
        require(
            msg.sender == creditManager,
            "REGISTERED_CREDIT_ACCOUNT_MANAGERS_ONLY"
        );
        _;
    }

    constructor() {
        // todo : build credit account contract
        masterCreditAccount = address(new CreditAccount());
        CreditAccount(masterCreditAccount).initialize();

        addCreditAccount();
        head = tail;
        _nextCreditAccount[address(0)] = address(0);
    }

    /// @dev set credit manager
    function setCreditManager(address _address) external onlyOwner {
        require(_address != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");
        creditManager = _address;
    }

    function takeCreditAccount(
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external creditManagerOnly returns (address) {
        // Create a new credit account if no one in stock
        _checkStock();

        address result = head;
        head = _nextCreditAccount[head];
        _nextCreditAccount[result] = address(0);

        // Initialize creditManager
        ICreditAccount(result).connectTo(
            msg.sender,
            _borrowedAmount,
            _cumulativeIndexAtOpen
        );

        emit InitializeCreditAccount(result, msg.sender);
        return result;
    }

    function returnCreditAccount(address usedAccount)
        external
        creditManagerOnly
    {
        require(
            creditAccountsSet.contains(usedAccount),
            "AF_EXTERNAL_ACCOUNTS_ARE_FORBIDDEN"
        );
        require(
            ICreditAccount(usedAccount).since() != block.number,
            "AF_CANT_CLOSE_CREDIT_ACCOUNT_IN_THE_SAME_BLOCK"
        );

        // take the used account back in the end of the stock
        _nextCreditAccount[tail] = usedAccount;
        // change tail to the last
        tail = usedAccount;
        emit ReturnCreditAccount(usedAccount);
    }

    function addCreditAccount() public {
        // use masterCreditAccount as implementation to create the new proxy contract
        address clonedAccount = Clones.clone(masterCreditAccount);
        ICreditAccount(clonedAccount).initialize();
        _nextCreditAccount[tail] = clonedAccount;
        tail = clonedAccount;
        creditAccountsSet.add(clonedAccount);
        emit NewCreditAccount(clonedAccount);
    }

    function _checkStock() internal {
        if (_nextCreditAccount[head] == address(0)) {
            addCreditAccount();
        }
    }
}
