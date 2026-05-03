// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public immutable duration;
    uint256 public immutable totalAmount;

    uint256 public released;

    event TokensReleased(address indexed beneficiary, uint256 amount);

    error NothingToRelease();
    error BeneficiaryZeroAddress();
    error DurationZero();

    constructor(
        address _token,
        address _beneficiary,
        uint256 _startTime,
        uint256 _duration,
        uint256 _totalAmount
    ) Ownable(msg.sender) {
        if (_beneficiary == address(0)) revert BeneficiaryZeroAddress();
        if (_duration == 0) revert DurationZero();

        token       = IERC20(_token);
        beneficiary = _beneficiary;
        startTime   = _startTime;
        duration    = _duration;
        totalAmount = _totalAmount;
    }

    function release() external {
        uint256 amount = vestedAmount() - released;
        if (amount == 0) revert NothingToRelease();

        released += amount;

        emit TokensReleased(beneficiary, amount);
        token.safeTransfer(beneficiary, amount);
    }

    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < startTime) {
            return 0;
        } else if (block.timestamp >= startTime + duration) {
            return totalAmount;
        } else {
            return (totalAmount * (block.timestamp - startTime)) / duration;
        }
    }

    function releasable() external view returns (uint256) {
        return vestedAmount() - released;
    }
}
