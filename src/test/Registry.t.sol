// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {Registry} from "../Registry.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";

contract TestRegistry is DSTestPlus {
    address public constant sampleAdd = address(0xabcd);
    string public constant sampleName = "gm";

    Registry public registry;

    function setUp() public {
        registry = new Registry();
    }

    function testClaim() public {
        registry.claim(sampleName);

        assertEq(registry.names(sampleName), address(this));
        assertEq(registry.lastClaimedAt(address(this)), block.timestamp);
    }

    function testClaimAlreadyClaimed() public {
        registry.claim(sampleName);

        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed()"));
        registry.claim(sampleName);
    }

    function testClaimEarlyClaim() public {
        registry.claim(sampleName);

        vm.expectRevert(abi.encodeWithSignature("EarlyClaim()"));
        registry.claim("gmm");
    }

    function testClaimMultipleNameSameAddress() public {
        registry.claim(sampleName);

        assertEq(registry.names(sampleName), address(this));
        assertEq(registry.lastClaimedAt(address(this)), block.timestamp);

        vm.warp(block.timestamp + 1 days);

        registry.claim("gmm");

        assertEq(registry.names("gmm"), address(this));
        assertEq(registry.lastClaimedAt(address(this)), block.timestamp);
    }

    function testClaimSameNameMultipleAddress() public {
        registry.claim(sampleName);

        vm.prank(sampleAdd);
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed()"));
        registry.claim(sampleName);
    }

    function testClaimMultipleNamesMultipleAddress() public {
        registry.claim(sampleName);

        vm.prank(sampleAdd);
        registry.claim("gmm");

        assertEq(registry.names("gmm"), sampleAdd);
    }

    function testClaimFuzz(string memory _name) public {
        registry.claim(_name);
    }

    function testRelease() public {
        registry.claim(sampleName);
        registry.release(sampleName);

        assertEq(registry.names(sampleName), address(0));
    }

    function testReleaseUnauthorised() public {
        registry.claim(sampleName);

        vm.expectRevert(abi.encodeWithSignature("Unauthorised()"));
        vm.prank(sampleAdd);
        registry.release(sampleName);
    }

    function testReleaseNotClaimed() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorised()"));
        registry.release(sampleName);
    }
}
