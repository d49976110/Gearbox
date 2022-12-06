// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract CreditAccount is Initializable {
    address public factory;

    function initialize() external initializer {
        factory = msg.sender;
    }
}
