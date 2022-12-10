// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library Constants {
    uint256 constant RAY = 1e27;
    uint256 constant WAD = 1e18;

    uint256 constant SECONDS_PER_YEAR = 365 days;

    // max fee is 1 % , 100 = 1%
    uint8 constant MAX_WITHDRAW_FEE = 100;

    // leverage decimals
    uint8 constant LEVERAGE_DECIMALS = 100;

    uint8 constant OPERATION_CLOSURE = 1;
    uint8 constant OPERATION_REPAY = 2;
    uint8 constant OPERATION_LIQUIDATION = 3;

    // FEE = 10%
    uint256 constant FEE_INTEREST = 1000; // 10%

    // FEE + LIQUIDATION_FEE 2% = 200
    uint256 constant FEE_LIQUIDATION = 200;

    // Liquidation premium 5% = 9500
    uint256 constant LIQUIDATION_DISCOUNTED_SUM = 9500;

    uint256 constant UNDERLYING_TOKEN_LIQUIDATION_THRESHOLD =
        LIQUIDATION_DISCOUNTED_SUM - FEE_LIQUIDATION;

    uint256 constant PERCENTAGE_FACTOR = 1e4;
}
