// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library Constants {
    uint256 constant RAY = 1e27;
    uint256 constant SECONDS_PER_YEAR = 365 days;

    // max fee is 1 % , 100 = 1%
    uint8 constant MAX_WITHDRAW_FEE = 100;

    // leverage decimals
    uint8 constant LEVERAGE_DECIMALS = 100;
}
