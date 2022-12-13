// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface ICreditFilter {
    function isTokenAllowed(address token) external view returns (bool);

    function initEnabledTokens(address creditAccount) external;

    function enabledTokens(address creditAccount)
        external
        view
        returns (uint256);

    function allowedTokensCount() external view returns (uint256);

    function getCreditAccountTokenById(address creditAccount, uint256 id)
        external
        view
        returns (
            address token,
            uint256 balance,
            uint256 tv,
            uint256 twv
        );

    function checkAndEnableToken(address token) external view returns (bool);

    function calcCreditAccountAccruedInterest(address creditAccount)
        external
        view
        returns (uint256);
}
