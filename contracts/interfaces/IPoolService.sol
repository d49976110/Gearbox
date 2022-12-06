// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IPoolService {
    function calcLinearCumulative_RAY() external view returns (uint256);

    function underlyingToken() external view returns (address);

    function lendCreditAccount(uint256 borrowedAmount, address creditAccount)
        external;
}
