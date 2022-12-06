// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IInterestRateModel {
    function calcBorrowRate() external view returns (uint256);
}
