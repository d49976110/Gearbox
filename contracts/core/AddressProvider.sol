// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AddressProvider is Ownable {
    address TreasuryContract;

    function setTreasuryContract(address _address) external onlyOwner {
        TreasuryContract = _address;
    }

    function getTreasuryContract() external view returns (address) {
        return TreasuryContract;
    }
}
