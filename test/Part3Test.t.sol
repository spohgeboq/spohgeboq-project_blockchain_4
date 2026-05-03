// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/GovernanceToken.sol";
import "../src/MyGovernor.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";

contract Part3Test is Test {
    GovernanceToken    public token;
    TimelockController public timelock;
    MyGovernor         public governor;
    Treasury           public treasury;
    Box                public box;

    address public deployer  = makeAddr("deployer");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");
    address public community = makeAddr("community");
    address public liquidity = makeAddr("liquidity");

    uint256 public constant TIMELOCK_DELAY = 2 days;

    function setUp() public {
        vm.startPrank(deployer);

        address[] memory noAddrs = new address[](0);

        timelock = new TimelockController(TIMELOCK_DELAY, noAddrs, noAddrs, deployer);

        token = new GovernanceToken(deployer, deployer, community, liquidity);

        governor = new MyGovernor(IVotes(address(token)), timelock);

        treasury = new Treasury(address(timelock));
        box      = new Box(address(timelock));

        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(),  address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        token.transfer(alice, 500_000 * 10 ** 18);
        token.transfer(bob,    50_000 * 10 ** 18);

        token.transfer(address(treasury), 10_000 * 10 ** 18);

        vm.stopPrank();

        vm.deal(address(treasury), 5 ether);

        vm.roll(block.number + 1);

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        vm.roll(block.number + 1);
    }

    function _fullGovernanceCycle(
        address _target,
        bytes memory _payload,
        string memory _desc
    ) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);

        targets[0] = _target;
        values[0]  = 0;
        calls[0]   = _payload;

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calls, _desc);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        governor.queue(targets, values, calls, keccak256(bytes(_desc)));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        governor.execute(targets, values, calls, keccak256(bytes(_desc)));
    }

    function test_boxOwnedByTimelock() public view {
        assertEq(box.owner(), address(timelock));
    }

    function test_treasuryOwnedByTimelock() public view {
        assertEq(treasury.owner(), address(timelock));
    }

    function test_treasuryReceivesEther() public view {
        assertEq(treasury.etherBalance(), 5 ether);
    }

    function test_treasuryReceivesTokens() public view {
        assertEq(treasury.tokenBalance(address(token)), 10_000 * 10 ** 18);
    }

    function test_directCallToBoxReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        box.store(999);
    }

    function test_directCallToTreasuryReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.transferEther(payable(alice), 1 ether);
    }

    function test_governanceBoxStore42() public {
        bytes memory payload = abi.encodeCall(Box.store, (42));
        _fullGovernanceCycle(address(box), payload, "Proposal: store 42 in Box");

        assertEq(box.retrieve(), 42);
    }

    function test_governanceBoxStoreArbitraryValue() public {
        bytes memory payload = abi.encodeCall(Box.store, (12345));
        _fullGovernanceCycle(address(box), payload, "Proposal: store 12345 in Box");

        assertEq(box.retrieve(), 12345);
    }

    function test_governanceBoxStoreUpdatesValue() public {
        bytes memory p1 = abi.encodeCall(Box.store, (10));
        _fullGovernanceCycle(address(box), p1, "Proposal: first store");
        assertEq(box.retrieve(), 10);

        bytes memory p2 = abi.encodeCall(Box.store, (20));
        _fullGovernanceCycle(address(box), p2, "Proposal: second store");
        assertEq(box.retrieve(), 20);
    }

    function test_governanceTransferEtherFromTreasury() public {
        address payable recipient = payable(makeAddr("recipient"));
        uint256 amount = 1 ether;

        uint256 balBefore = recipient.balance;

        bytes memory payload = abi.encodeCall(Treasury.transferEther, (recipient, amount));
        _fullGovernanceCycle(address(treasury), payload, "Proposal: send 1 ETH from treasury");

        assertEq(recipient.balance, balBefore + amount);
        assertEq(treasury.etherBalance(), 4 ether);
    }

    function test_governanceTransferTokenFromTreasury() public {
        address recipient = makeAddr("recipient2");
        uint256 amount = 500 * 10 ** 18;

        bytes memory payload = abi.encodeCall(
            Treasury.transferToken,
            (address(token), recipient, amount)
        );
        _fullGovernanceCycle(address(treasury), payload, "Proposal: transfer 500 GTK from treasury");

        assertEq(token.balanceOf(recipient), amount);
        assertEq(treasury.tokenBalance(address(token)), 10_000 * 10 ** 18 - amount);
    }

    function test_boxStoreEventEmitted() public {
        bytes memory payload = abi.encodeCall(Box.store, (77));

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(box);
        calls[0]   = payload;
        string memory desc = "Proposal: emit event store 77";

        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calls, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(id, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calls, keccak256(bytes(desc)));
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        vm.expectEmit(true, true, true, true);
        emit Box.ValueStored(77);

        governor.execute(targets, values, calls, keccak256(bytes(desc)));
    }

    function test_fullLifecycleStatesBox42() public {
        bytes memory payload = abi.encodeCall(Box.store, (42));
        string memory desc = "E2E: store 42 in Box";

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(box);
        calls[0]   = payload;

        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calls, desc);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));

        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));

        vm.prank(alice);
        governor.castVote(id, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, calls, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calls, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));

        assertEq(box.retrieve(), 42);
    }

    function test_treasuryCanReceiveEtherDirectly() public {
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(treasury.etherBalance(), 6 ether);
    }

    function test_boxDefaultValueIsZero() public view {
        assertEq(box.retrieve(), 0);
    }
}
