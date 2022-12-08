// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface ICreditFilter {
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
}
