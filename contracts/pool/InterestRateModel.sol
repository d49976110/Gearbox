// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

contract InterestRateModel {
    // fix interest rate is 5 %
    function calcBorrowRate() external pure returns (uint256) {
        // because constants RAY is 1e27
        return 5 * 1e25;
    }
}
