// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IAccountFactory.sol";
import "../interfaces/IPoolService.sol";
import "../interfaces/ICreditFilter.sol";

import "../libraries/helpers/Constants.sol";

contract CreditManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public minAmount;
    uint256 public maxAmount;
    uint256 public maxLeverageFactor;

    address public underlyingToken;
    address public poolService;

    mapping(address => address) public creditAccounts;

    IAccountFactory internal _accountFactory;
    ICreditFilter public creditFilter;

    event OpenCreditAccount(
        address indexed sender,
        address indexed onBehalfOf,
        address indexed creditAccount,
        uint256 amount,
        uint256 borrowAmount,
        uint256 referralCode
    );

    function openCreditAccount(
        uint256 amount,
        address onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    ) external whenNotPaused nonReentrant {
        require(
            amount >= minAmount &&
                amount <= maxAmount &&
                leverageFactor > 0 &&
                leverageFactor <= maxLeverageFactor,
            "CM_INCORRECT_PARAMS"
        );

        require(
            onBehalfOf != address(0) && !hasOpenedCreditAccount(onBehalfOf),
            "CM_ZERO_ADDRESS_OR_USER_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT"
        );

        // if leverage is 4, so leverageFactor should be 400, because LEVERAGE_DECIMALS is 100
        uint256 borrowedAmount = (amount * leverageFactor) /
            Constants.LEVERAGE_DECIMALS;

        // todo : finish account factory
        // Get Reusable Credit account creditAccount
        address creditAccount = _accountFactory.takeCreditAccount(
            borrowedAmount,
            IPoolService(poolService).calcLinearCumulative_RAY()
        ); // T:[CM-5]

        // Initializes enabled tokens for the account. Enabled tokens is a bit mask which
        // holds information which tokens were used by user
        creditFilter.initEnabledTokens(creditAccount);

        // Transfer pool tokens to new credit account
        IPoolService(poolService).lendCreditAccount(
            borrowedAmount,
            creditAccount
        ); // T:[CM-7]

        // Transfer borrower own fund to credit account
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            creditAccount,
            amount
        ); // T:[CM-6]

        // link credit account address with borrower address
        creditAccounts[onBehalfOf] = creditAccount;

        // emit new event
        emit OpenCreditAccount(
            msg.sender,
            onBehalfOf,
            creditAccount,
            amount,
            borrowedAmount,
            referralCode
        );
    }

    function hasOpenedCreditAccount(address borrower)
        public
        view
        returns (bool)
    {
        return creditAccounts[borrower] != address(0); // T:[CM-26]
    }

    function _checkAccountTransfer(address newOwner) internal view {
        require(
            newOwner != address(0) && !hasOpenedCreditAccount(newOwner),
            "CM_ZERO_ADDRESS_OR_USER_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT"
        );
    }
}
