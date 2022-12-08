// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IAccountFactory {
    function takeCreditAccount(
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external returns (address);

    function returnCreditAccount(address usedAccount) external;
}
