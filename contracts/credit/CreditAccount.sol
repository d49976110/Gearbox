// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract CreditAccount is Initializable {
    using SafeERC20 for IERC20;
    using Address for address;

    address public factory;
    address public creditManager;

    // Amount borrowed from the pool
    uint256 public borrowedAmount;
    uint256 public cumulativeIndexAtOpen;
    uint256 public since;

    modifier creditManagerOnly() {
        require(
            msg.sender == creditManager,
            "CA_CONNECTED_CREDIT_MANAGER_ONLY"
        );
        _;
    }

    // factory wil be account factory
    function initialize() external initializer {
        factory = msg.sender;
    }

    ///@dev  coneect to credit manager
    function connectTo(
        address _creditManager,
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external {
        require(msg.sender == factory, "CA_FACTORY_ONLY");
        creditManager = _creditManager;
        borrowedAmount = _borrowedAmount;
        cumulativeIndexAtOpen = _cumulativeIndexAtOpen;
        since = block.number;
    }

    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) external creditManagerOnly {
        IERC20(token).safeTransfer(to, amount);
    }

    function approveToken(address token, address swapContract)
        external
        creditManagerOnly
    {
        //using safe approve, so we need to rest approve to 0 first
        IERC20(token).safeApprove(swapContract, 0);
        IERC20(token).safeApprove(swapContract, type(uint256).max);
    }

    function execute(address destination, bytes memory data)
        external
        creditManagerOnly
        returns (bytes memory)
    {
        return destination.functionCall(data);
    }
}
