// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";

contract Part1Test is Test {
    GovernanceToken public token;
    TokenVesting    public vesting;

    address public team      = makeAddr("team");
    address public treasury  = makeAddr("treasury");
    address public community = makeAddr("community");
    address public liquidity = makeAddr("liquidity");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");

    uint256 public constant DURATION = 365 days;

    function setUp() public {
        vesting = new TokenVesting(
            address(0),
            team,
            block.timestamp,
            DURATION,
            0
        );

        token = new GovernanceToken(address(vesting), treasury, community, liquidity);

        vesting = new TokenVesting(
            address(token),
            team,
            block.timestamp,
            DURATION,
            token.TEAM_ALLOCATION()
        );
    }

    function test_totalSupply() public view {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function test_initialDistribution() public view {
        assertEq(token.balanceOf(treasury),  token.TREASURY_ALLOCATION());
        assertEq(token.balanceOf(community), token.COMMUNITY_ALLOCATION());
        assertEq(token.balanceOf(liquidity), token.LIQUIDITY_ALLOCATION());
    }

    function test_delegateSelf() public {
        vm.startPrank(treasury);
        token.delegate(treasury);
        vm.stopPrank();

        assertEq(token.getVotes(treasury), token.TREASURY_ALLOCATION());
    }

    function test_delegateToAnother() public {
        vm.startPrank(treasury);
        token.delegate(alice);
        vm.stopPrank();

        assertEq(token.getVotes(alice),    token.TREASURY_ALLOCATION());
        assertEq(token.getVotes(treasury), 0);
    }

    function test_votingPowerSnapshot() public {
        vm.startPrank(treasury);
        token.delegate(treasury);
        vm.stopPrank();

        uint256 blockA = block.number;
        vm.roll(block.number + 1);

        vm.prank(treasury);
        token.transfer(alice, 1000 * 10 ** 18);

        uint256 pastVotes = token.getPastVotes(treasury, blockA);
        assertEq(pastVotes, token.TREASURY_ALLOCATION());
    }

    function test_permit() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        deal(address(token), signer, 500 * 10 ** 18);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount   = 100 * 10 ** 18;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            signer,
                            alice,
                            amount,
                            token.nonces(signer),
                            deadline
                        )
                    )
                )
            )
        );

        token.permit(signer, alice, amount, deadline, v, r, s);
        assertEq(token.allowance(signer, alice), amount);
    }

    function test_vestingLinearRelease() public {
        uint256 half = DURATION / 2;
        vm.warp(block.timestamp + half);

        uint256 expected = token.TEAM_ALLOCATION() / 2;
        uint256 actualVested = vesting.vestedAmount();

        assertApproxEqAbs(actualVested, expected, 1e18);
    }

    function test_vestingFullRelease() public {
        vm.warp(block.timestamp + DURATION + 1);

        assertEq(vesting.vestedAmount(), token.TEAM_ALLOCATION());
    }

    function test_vestingReleaseTokens() public {
        uint256 half = DURATION / 2;
        vm.warp(block.timestamp + half);

        uint256 balBefore = token.balanceOf(team);

        vm.prank(team);
        deal(address(token), address(vesting), token.TEAM_ALLOCATION());
        vesting.release();

        uint256 balAfter = token.balanceOf(team);
        assertGt(balAfter, balBefore);
    }

    function test_vestingBeforeStart() public {
        TokenVesting futureVesting = new TokenVesting(
            address(token),
            team,
            block.timestamp + 1 days,
            DURATION,
            token.TEAM_ALLOCATION()
        );

        assertEq(futureVesting.vestedAmount(), 0);
    }

    function test_noDelegationMeansNoVotes() public view {
        assertEq(token.getVotes(treasury), 0);
    }

    function test_delegationTransfer() public {
        vm.prank(treasury);
        token.delegate(alice);

        uint256 transfer = 100 * 10 ** 18;
        vm.prank(treasury);
        token.transfer(bob, transfer);

        uint256 expected = token.TREASURY_ALLOCATION() - transfer;
        assertEq(token.getVotes(alice), expected);
    }
}
