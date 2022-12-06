// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ICreditManager.sol";
import "../interfaces/IPoolService.sol";

contract CreditFilter is Ownable, Pausable, ReentrancyGuard {
    address public creditManager;
    address public poolService;
    address public underlyingToken;

    mapping(address => uint256) public enabledTokens;
    mapping(address => uint256) public fastCheckCounter;

    modifier creditManagerOnly() {
        require(msg.sender == creditManager, "CF_CREDIT_MANAGERS_ONLY");
        _;
    }

    function initEnabledTokens(address creditAccount)
        external
        creditManagerOnly
    {
        // at opening account underlying token is enabled only
        enabledTokens[creditAccount] = 1;
        fastCheckCounter[creditAccount] = 1;
    }

    function connectCreditManager(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");
        // only can set once
        require(
            creditManager == address(0),
            "CF_CREDIT_MANAGER_IS_ALREADY_SET"
        );

        creditManager = _creditManager; // T:[CF-14]
        poolService = ICreditManager(_creditManager).poolService(); //  T:[CF-14]

        require(
            IPoolService(poolService).underlyingToken() == underlyingToken,
            "CF_UNDERLYING_TOKEN_FILTER_CONFLICT"
        );
    }
}
