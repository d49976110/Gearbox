// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface ICreditAccount {
    function initialize() external;

    function connectTo(
        address _creditManager,
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external;
}
