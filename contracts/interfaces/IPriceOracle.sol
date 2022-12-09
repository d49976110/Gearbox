// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IPriceOracle {
    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view returns (uint256);
}
