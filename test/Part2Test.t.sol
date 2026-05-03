// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/GovernanceToken.sol";
import "../src/MyGovernor.sol";

contract MockTarget {
    uint256 public value;
    uint256 public fee;

    function store(uint256 _value) external {
        value = _value;
    }

    function setFee(uint256 _fee) external {
        fee = _fee;
    }
}

contract Part2Test is Test {
    GovernanceToken    public token;
    TimelockController public timelock;
    MyGovernor         public governor;
    MockTarget         public target;

    address public deployer  = makeAddr("deployer");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");
    address public carol     = makeAddr("carol");
    address public treasury  = makeAddr("treasury");
    address public community = makeAddr("community");
    address public liquidity = makeAddr("liquidity");

    uint256 public constant TIMELOCK_DELAY = 2 days;

    function setUp() public {
        vm.startPrank(deployer);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0);
        executors[0] = address(0);

        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        token = new GovernanceToken(deployer, address(timelock), community, liquidity);

        governor = new MyGovernor(IVotes(address(token)), timelock);

        token.transfer(alice, 200_000 * 10 ** 18);
        token.transfer(bob,   50_000 * 10 ** 18);

        target = new MockTarget();

        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(PROPOSER_ROLE, address(0));
        timelock.revokeRole(ADMIN_ROLE, deployer);

        vm.stopPrank();

        vm.roll(block.number + 1);

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        vm.roll(block.number + 1);
    }

    function _propose(
        address _target,
        bytes memory _calldata,
        string memory _desc
    ) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);

        targets[0] = _target;
        values[0]  = 0;
        calls[0]   = _calldata;

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calls, _desc);
    }

    function _passProposal(uint256 proposalId) internal {
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
    }

    function _queueAndExecute(
        address _target,
        bytes memory _calldata,
        string memory _desc
    ) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);

        targets[0] = _target;
        values[0]  = 0;
        calls[0]   = _calldata;

        vm.roll(block.number + governor.votingPeriod() + 1);

        governor.queue(targets, values, calls, keccak256(bytes(_desc)));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        governor.execute(targets, values, calls, keccak256(bytes(_desc)));
    }

    function test_governorParameters() public view {
        assertEq(governor.votingDelay(),  7200);
        assertEq(governor.votingPeriod(), 50400);
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalThreshold() public view {
        uint256 supply    = token.getPastTotalSupply(block.number - 1);
        uint256 threshold = (supply * 100) / 10_000;
        assertEq(governor.proposalThreshold(), threshold);
    }

    function test_timelockIsExecutor() public view {
        assertEq(governor.timelock(), address(timelock));
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_proposeAndGetState() public {
        uint256 id = _propose(address(target), abi.encodeCall(MockTarget.store, (42)), "Store 42");
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));
    }

    function test_proposalBecomesActive() public {
        uint256 id = _propose(address(target), abi.encodeCall(MockTarget.store, (42)), "Store 42");
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));
    }

    function test_fullLifecycleStoreValue() public {
        string memory desc    = "Proposal: store 42 in target";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (42));

        uint256 id = _propose(address(target), payload, desc);
        _passProposal(id);
        _queueAndExecute(address(target), payload, desc);

        assertEq(target.value(), 42);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_fullLifecycleSetFee() public {
        string memory desc    = "Proposal: set fee to 500";
        bytes  memory payload = abi.encodeCall(MockTarget.setFee, (500));

        uint256 id = _propose(address(target), payload, desc);
        _passProposal(id);
        _queueAndExecute(address(target), payload, desc);

        assertEq(target.fee(), 500);
    }

    function test_quorumNotMet() public {
        vm.prank(deployer);
        token.transfer(carol, 100 * 10 ** 18);
        vm.prank(carol);
        token.delegate(carol);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(target);
        calls[0]   = abi.encodeCall(MockTarget.store, (99));

        vm.prank(carol);
        vm.expectRevert();
        governor.propose(targets, values, calls, "Carol small proposal");
    }

    function test_proposalDefeated() public {
        string memory desc    = "Proposal: contested";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (1));

        uint256 id = _propose(address(target), payload, desc);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(id, 0);

        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_delegateeVotesOnBehalfOfDelegator() public {
        address delegator = makeAddr("delegator");
        address delegatee = makeAddr("delegatee");

        deal(address(token), delegator, 100_000 * 10 ** 18);

        vm.prank(delegator);
        token.delegate(delegatee);
        vm.roll(block.number + 1);

        string memory desc    = "Proposal: delegatee votes";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (7));

        uint256 id = _propose(address(target), payload, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(delegatee);
        governor.castVote(id, 1);

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(id);

        assertGt(forVotes, 0);
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_castVoteWithReason() public {
        string memory desc    = "Proposal: vote with reason";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (10));

        uint256 id = _propose(address(target), payload, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVoteWithReason(id, 1, "I support this change");

        (, uint256 forVotes, ) = governor.proposalVotes(id);
        assertGt(forVotes, 0);
    }

    function test_abstainVote() public {
        string memory desc    = "Proposal: abstain";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (11));

        uint256 id = _propose(address(target), payload, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(id, 2);

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(id);
        assertGt(abstain, 0);
        assertEq(forVotes, 0);
        assertEq(against, 0);
    }

    function test_cannotVoteTwice() public {
        string memory desc    = "Proposal: double vote";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (12));

        uint256 id = _propose(address(target), payload, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(alice);
        governor.castVote(id, 1);
        vm.expectRevert();
        governor.castVote(id, 1);
        vm.stopPrank();
    }

    function test_queuedStateAfterSuccess() public {
        string memory desc    = "Proposal: queue state";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (13));

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(target);
        calls[0]   = payload;

        uint256 id = _propose(address(target), payload, desc);
        _passProposal(id);

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, calls, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));
    }

    function test_cannotExecuteBeforeTimelockExpiry() public {
        string memory desc    = "Proposal: timelock guard";
        bytes  memory payload = abi.encodeCall(MockTarget.store, (99));

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(target);
        calls[0]   = payload;

        uint256 id = _propose(address(target), payload, desc);
        _passProposal(id);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calls, keccak256(bytes(desc)));

        vm.expectRevert();
        governor.execute(targets, values, calls, keccak256(bytes(desc)));
    }

    function test_transferTokensFromTreasury() public {
        address recipient = makeAddr("recipient");
        uint256 amount    = 1_000 * 10 ** 18;

        string memory desc    = "Proposal: transfer from treasury";
        bytes  memory payload = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            amount
        );

        address[] memory targets = new address[](1);
        uint256[] memory values  = new uint256[](1);
        bytes[]   memory calls   = new bytes[](1);
        targets[0] = address(token);
        values[0]  = 0;
        calls[0]   = payload;

        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calls, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(id, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calls, keccak256(bytes(desc)));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calls, keccak256(bytes(desc)));

        assertEq(token.balanceOf(recipient), amount);
    }
}
