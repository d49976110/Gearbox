// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library DataTypes {
    struct Exchange {
        address[] path;
        uint256 amountOutMin;
    }
}
