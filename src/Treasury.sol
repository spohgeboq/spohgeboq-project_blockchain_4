// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    event EtherReceived(address indexed sender, uint256 amount);
    event EtherTransferred(address indexed to, uint256 amount);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error InsufficientEtherBalance();
    error InsufficientTokenBalance();
    error TransferFailed();

    constructor(address _timelockController) Ownable(_timelockController) {}

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    function transferEther(address payable _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (address(this).balance < _amount) revert InsufficientEtherBalance();

        emit EtherTransferred(_to, _amount);

        (bool ok, ) = _to.call{value: _amount}("");
        if (!ok) revert TransferFailed();
    }

    function transferToken(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (IERC20(_token).balanceOf(address(this)) < _amount) revert InsufficientTokenBalance();

        emit TokenTransferred(_token, _to, _amount);

        IERC20(_token).safeTransfer(_to, _amount);
    }

    function etherBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
