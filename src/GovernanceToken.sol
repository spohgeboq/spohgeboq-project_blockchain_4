// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10 ** 18;

    uint256 public constant TEAM_ALLOCATION      = (TOTAL_SUPPLY * 40) / 100;
    uint256 public constant TREASURY_ALLOCATION  = (TOTAL_SUPPLY * 30) / 100;
    uint256 public constant COMMUNITY_ALLOCATION = (TOTAL_SUPPLY * 20) / 100;
    uint256 public constant LIQUIDITY_ALLOCATION = (TOTAL_SUPPLY * 10) / 100;

    address public immutable vestingContract;

    constructor(
        address _teamVesting,
        address _treasury,
        address _communityMultisig,
        address _liquidityPool
    )
        ERC20("GovernanceToken", "GTK")
        ERC20Permit("GovernanceToken")
        Ownable(msg.sender)
    {
        vestingContract = _teamVesting;

        _mint(_teamVesting,       TEAM_ALLOCATION);
        _mint(_treasury,          TREASURY_ALLOCATION);
        _mint(_communityMultisig, COMMUNITY_ALLOCATION);
        _mint(_liquidityPool,     LIQUIDITY_ALLOCATION);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
