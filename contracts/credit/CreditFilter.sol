// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ICreditManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IPoolService.sol";
import "../libraries/helpers/Constants.sol";

contract CreditFilter is Ownable, Pausable, ReentrancyGuard {
    address public creditManager;
    address public poolService;
    address public underlyingToken;
    address public priceOracle;

    address[] public allowedTokens;
    mapping(address => bool) public isTokenAllowed;
    mapping(address => uint256) public liquidationThresholds;

    mapping(address => uint256) public enabledTokens;
    mapping(address => uint256) public fastCheckCounter;

    modifier creditManagerOnly() {
        require(msg.sender == creditManager, "CREDIT_MANAGERS_ONLY");
        _;
    }

    constructor(address _priceOracle, address _underlyingToken) {
        require(_underlyingToken != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        priceOracle = _priceOracle;

        underlyingToken = _underlyingToken;

        liquidationThresholds[underlyingToken] = Constants
            .UNDERLYING_TOKEN_LIQUIDATION_THRESHOLD;

        _allowToken(underlyingToken);
    }

    /// @dev credit manager will do this when open credit account
    function initEnabledTokens(address creditAccount)
        external
        creditManagerOnly
    {
        // at opening account underlying token is enabled only
        enabledTokens[creditAccount] = 1;
        // fastCheckCounter[creditAccount] = 1;
    }

    ///@dev connect to credit manager
    function connectCreditManager(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");
        // only can set once
        require(
            creditManager == address(0),
            "CF_CREDIT_MANAGER_IS_ALREADY_SET"
        );

        creditManager = _creditManager;
        poolService = ICreditManager(_creditManager).poolService();

        require(
            IPoolService(poolService).underlyingToken() == underlyingToken,
            "CF_UNDERLYING_TOKEN_FILTER_CONFLICT"
        );
    }

    function allowToken(address _token) external onlyOwner {
        require(!isTokenAllowed[_token], "ALREADY IN LIST");

        _allowToken(_token);
    }

    function _allowToken(address _token) internal {
        isTokenAllowed[_token] = true;
        allowedTokens.push(_token);
    }

    function allowedTokensCount() external view returns (uint256) {
        return allowedTokens.length;
    }

    function getCreditAccountTokenById(address creditAccount, uint256 id)
        public
        view
        returns (
            address token,
            uint256 balance,
            uint256 tv,
            uint256 tvw
        )
    {
        token = allowedTokens[id];
        balance = IERC20(token).balanceOf(creditAccount);

        if (balance > 1) {
            tv = IPriceOracle(priceOracle).convert(
                balance,
                token,
                underlyingToken
            );
            tvw = tv * liquidationThresholds[token];
        }
    }
}
