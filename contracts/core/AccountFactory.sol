// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../credit/CreditAccount.sol";
import "../interfaces/ICreditAccount.sol";

contract AccountFactory is Ownable, Pausable, ReentrancyGuard {
    address public creditManager;

    address public head;
    address public tail;
    mapping(address => address) private _nextCreditAccount;

    address public masterCreditAccount;

    event NewCreditAccount(address indexed account);
    event InitializeCreditAccount(
        address indexed account,
        address indexed creditManager
    );

    modifier creditManagerOnly() {
        require(
            msg.sender == creditManager,
            "REGISTERED_CREDIT_ACCOUNT_MANAGERS_ONLY"
        );
        _;
    }

    // todo : not finish other functions
    constructor(address addressProvider) {
        require(addressProvider != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        // todo : build credit account contract
        masterCreditAccount = address(new CreditAccount());
        CreditAccount(masterCreditAccount).initialize();

        addCreditAccount();
        head = tail;
        _nextCreditAccount[address(0)] = address(0);
    }

    function setCreditManager(address _address) external onlyOwner {
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

    // todo : understanding the EnumerableSet.AddressSet
    function addCreditAccount() public {
        // use masterCreditAccount as implementation to create the new proxy contract
        address clonedAccount = Clones.clone(masterCreditAccount);
        ICreditAccount(clonedAccount).initialize();
        _nextCreditAccount[tail] = clonedAccount;
        tail = clonedAccount;
        // creditAccountsSet.add(clonedAccount);
        emit NewCreditAccount(clonedAccount);
    }

    function _checkStock() internal {
        if (_nextCreditAccount[head] == address(0)) {
            addCreditAccount();
        }
    }
}
