// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";
import "../src/MyGovernor.sol";
import "../src/Treasury.sol";
import "../src/Box.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployDAO is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        address[] memory noAddrs = new address[](0);
        TimelockController timelock = new TimelockController(
            2 days,
            noAddrs,
            noAddrs,
            deployer
        );

        GovernanceToken token = new GovernanceToken(
            deployer,
            address(timelock),
            deployer,
            deployer
        );

        MyGovernor governor = new MyGovernor(IVotes(address(token)), timelock);

        Treasury treasury = new Treasury(address(timelock));
        Box box = new Box(address(timelock));

        TokenVesting vesting = new TokenVesting(
            address(token),
            deployer,
            block.timestamp,
            365 days,
            token.TEAM_ALLOCATION()
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        token.delegate(deployer);

        vm.stopBroadcast();

        console.log("=== DEPLOYED ADDRESSES ===");
        console.log("GovernanceToken:", address(token));
        console.log("TokenVesting:   ", address(vesting));
        console.log("TimelockController:", address(timelock));
        console.log("MyGovernor:     ", address(governor));
        console.log("Treasury:       ", address(treasury));
        console.log("Box:            ", address(box));
        console.log("==========================");
    }
}
