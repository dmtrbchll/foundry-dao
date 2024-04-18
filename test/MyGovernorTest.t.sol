// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    TimeLock timelock;
    GovToken govToken;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks until a vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.prank(USER);
        govToken.delegate(USER); // we need this call to obtain voting power
        timelock = new TimeLock(MIN_DELAY, proposers, executors, address(this)); // with this setup anyone can propose and execute (array empty)
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        // only the governor can propose stuff to the timelock
        timelock.grantRole(proposerRole, address(governor));
        // everyone can execute passed proposal
        timelock.grantRole(executorRole, address(0));
        // the user will no longer be the admin
        timelock.revokeRole(adminRole, address(this));

        // the timelock owns the dao and the dao owns the timelock
        //  the timelock should execute the call after proposal passes
        box = new Box(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    // TODO: TEST NOT WORKING NEED TO DEBUG
    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 888 in the box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature(
            "store(uint256)",
            valueToStore
        );
        values.push(0); // 0 means no value to send
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        // View the state
        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "cuz dimkula is shmexy";
        uint8 voteWay = 1; // voting yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
