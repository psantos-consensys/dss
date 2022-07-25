// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2022 Horsefacts <horsefacts@terminally.online>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.5.16;

import {DSTest} from "ds-test/test.sol";

import {Sum} from "../../src/sum.sol";
import {CTR} from "../../src/gov/ctr.sol";
import {DSToken} from "ds-token/token.sol";
import {DSChief, DSChiefFab} from "ds-chief/chief.sol";
import {DSPause, DSPauseProxy} from "ds-pause/pause.sol";
import {DSSpell, DSSpellBook} from "ds-spell/spell.sol";

interface VmLike {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert(bytes calldata) external;
    function expectRevert(bytes4) external;
    function expectRevert() external;
    function label(address, string calldata) external;
}

contract TestGov is DSTest {

    // Can't use forge-std Test here
    address constant private VM_ADDRESS = address(bytes20(uint160(uint256(keccak256('hevm cheat code')))));
    VmLike public constant vm = VmLike(VM_ADDRESS);

    Sum internal sum;
    CTR internal ctr;
    DSChiefFab internal chiefFab;
    DSChief internal chief;
    DSPause internal pause;
    DSPauseProxy internal pauseProxy;
    DSSpellBook internal spellBook;
    DSSpell internal spell;

    address me = address(this);

    address alice = mkaddr('alice');
    address bob   = mkaddr('bob');
    address carol = mkaddr('carol');
    address dan   = mkaddr('dan');
    address eve   = mkaddr('eve');

    function mkaddr(string memory name) public returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encodePacked(name)))));
        vm.label(addr, name);
    }

    function setUp() public {
        sum = new Sum();
        ctr = new CTR();
        chiefFab = new DSChiefFab();
        chief = chiefFab.newChief(ctr, 5);

        pause = new DSPause(172800, address(0), address(chief));
        pauseProxy = pause.proxy();

        spellBook = new DSSpellBook();

        // Assemble the plot
        address      usr = address(sum);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(bytes32,uint)", "One", 2);
        uint256      eta = now + pause.delay();

        bytes memory plot = abi.encodeWithSignature(
            "plot(address,bytes32,bytes memory,uint)",
            usr,
            tag,
            fax,
            eta
        );
        spell = spellBook.make(address(pause), 0, plot);
    }

    function test_governance_deployment() public {
        // Chief has no owner
        assertEq(chief.owner(), address(0));

        // Deployer address is ward of Sum
        assertEq(sum.wards(me), 1);

        // Deployer can call privileged operations on Sum
        sum.file("One", 2);
        assertEq(sum.One(), 2);

        sum.file("One", 1);
        assertEq(sum.One(), 1);

        // Authorize Pause proxy
        sum.rely(address(pauseProxy));

        // Pause proxy address is ward of Sum
        assertEq(sum.wards(address(pauseProxy)), 1);

        // Pause proxy can call privileged operations on Sum
        vm.startPrank(address(pauseProxy));
        sum.file("One", 2);
        assertEq(sum.One(), 2);

        sum.file("One", 1);
        assertEq(sum.One(), 1);
        vm.stopPrank();

        // Renounce deployer access to Sum
        sum.deny(me);

        // Deployer address is no longer ward of Sum
        assertEq(sum.wards(me), 0);

        // Cannot call privileged operations on Sum
        vm.expectRevert("Sum/not-authorized");
        sum.file("One", 2);

        // Deployer address holds full CTR supply
        assertEq(ctr.balanceOf(me), ctr.totalSupply());

        // Transfer to voters
        ctr.push(alice, 100_000 ether);
        ctr.push(bob,   200_000 ether);
        ctr.push(carol, 300_000 ether);

        // Approvals to Chief
        vm.prank(alice);
        ctr.approve(address(chief), 100_000 ether);

        vm.prank(bob);
        ctr.approve(address(chief), 200_000 ether);

        vm.prank(carol);
        ctr.approve(address(chief), 300_000 ether);

        // Alice locks CTR
        vm.prank(alice);
        chief.lock(100_000 ether);

        // Bob locks CTR
        vm.prank(bob);
        chief.lock(200_000 ether);

        // Carol locks CTR
        vm.prank(carol);
        chief.lock(300_000 ether);

        // Create slates
        address[] memory dummy = new address[](1);
        dummy[0] = address(0);

        address[] memory slate = new address[](1);
        slate[0] = address(spell);

        // Hat is address(0)
        assertEq(chief.hat(), address(0));

        // Alice votes for spell slate
        vm.prank(alice);
        bytes32 slateId = chief.vote(slate);

        // Lift the hat
        chief.lift(address(spell));
        assertEq(chief.hat(), address(spell));

        // Bob votes for dummy slate
        vm.prank(bob);
        chief.vote(dummy);

        // Lift the hat
        chief.lift(address(0));
        assertEq(chief.hat(), address(0));

        // Carol votes for spell slate
        vm.prank(carol);
        chief.vote(slateId);

        // Lift the hat
        chief.lift(address(spell));
        assertEq(chief.hat(), address(spell));

        // Cast the spell
        //spell.cast();
    }

}
