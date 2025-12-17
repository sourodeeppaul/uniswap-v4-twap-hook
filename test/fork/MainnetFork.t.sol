// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/// @title MainnetForkTest
/// @notice Fork tests against mainnet
contract MainnetForkTest is Test {
    function setUp() public {
        // Fork mainnet
        // vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function test_fork_placeholder() public {
        assertTrue(true);
    }
}
