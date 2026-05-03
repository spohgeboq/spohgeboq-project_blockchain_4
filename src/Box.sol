// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Box is Ownable {
    uint256 private _value;

    event ValueStored(uint256 newValue);

    constructor(address _timelockController) Ownable(_timelockController) {}

    function store(uint256 newValue) external onlyOwner {
        _value = newValue;
        emit ValueStored(newValue);
    }

    function retrieve() external view returns (uint256) {
        return _value;
    }
}
