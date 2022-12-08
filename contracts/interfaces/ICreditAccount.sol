// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface ICreditAccount {
    function initialize() external;

    function borrowedAmount() external view returns (uint256);

    function cumulativeIndexAtOpen() external view returns (uint256);

    function connectTo(
        address _creditManager,
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external;

    function since() external view returns (uint256);

    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) external;

    function approveToken(address token, address swapContract) external;

    function execute(address destination, bytes memory data)
        external
        returns (bytes memory);
}
