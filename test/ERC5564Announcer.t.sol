// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC5564Announcer, IERC5564Announcer} from "../src/ERC5564Announcer.sol";

contract ERC5564AnnouncerTest is Test {
    ERC5564Announcer internal announcer;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stealthAddr = makeAddr("stealthAddr");

    function setUp() public {
        announcer = new ERC5564Announcer();
    }

    // ---- announce / evento ----

    function test_Announce_EmitsEvent() public {
        uint256 schemeId = 1;
        bytes memory ephemeralPubKey = hex"02aabbcc";
        bytes memory metadata = hex"f1";

        vm.expectEmit(true, true, true, true, address(announcer));
        emit IERC5564Announcer.Announcement(schemeId, stealthAddr, alice, ephemeralPubKey, metadata);

        vm.prank(alice);
        announcer.announce(schemeId, stealthAddr, ephemeralPubKey, metadata);
    }

    function test_Announce_WithEmptyMetadata() public {
        uint256 schemeId = 1;
        bytes memory ephemeralPubKey = hex"03ddeeff";
        bytes memory metadata = "";

        vm.expectEmit(true, true, true, true, address(announcer));
        emit IERC5564Announcer.Announcement(schemeId, stealthAddr, alice, ephemeralPubKey, metadata);

        vm.prank(alice);
        announcer.announce(schemeId, stealthAddr, ephemeralPubKey, metadata);
    }

    function test_Announce_WithNonEmptyMetadata() public {
        uint256 schemeId = 1;
        bytes memory ephemeralPubKey = hex"02aabbccddeeff00112233445566778899aabbccddeeff0011223344556677";
        // primer byte = view tag, resto = padding arbitrario de metadata.
        bytes memory metadata = hex"a1b2c3d4";

        vm.expectEmit(true, true, true, true, address(announcer));
        emit IERC5564Announcer.Announcement(schemeId, stealthAddr, alice, ephemeralPubKey, metadata);

        vm.prank(alice);
        announcer.announce(schemeId, stealthAddr, ephemeralPubKey, metadata);
    }

    function test_Announce_DifferentSchemeIds() public {
        uint256[3] memory schemeIds = [uint256(0), uint256(1), uint256(999)];

        for (uint256 i = 0; i < schemeIds.length; i++) {
            vm.expectEmit(true, true, true, true, address(announcer));
            emit IERC5564Announcer.Announcement(schemeIds[i], stealthAddr, alice, hex"01", hex"02");

            vm.prank(alice);
            announcer.announce(schemeIds[i], stealthAddr, hex"01", hex"02");
        }
    }

    /// @notice El `caller` que queda registrado en el evento es siempre
    ///         `msg.sender`, sin importar quién sea — el announcer no tiene
    ///         permisos ni whitelist: cualquiera puede anunciar cualquier cosa.
    function test_Announce_CallerIsAlwaysMsgSender() public {
        vm.expectEmit(true, true, true, true, address(announcer));
        emit IERC5564Announcer.Announcement(1, stealthAddr, bob, hex"01", hex"02");

        vm.prank(bob);
        announcer.announce(1, stealthAddr, hex"01", hex"02");
    }

    function test_Announce_AnyoneCanCall() public {
        address[3] memory callers = [alice, bob, makeAddr("carol")];

        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            announcer.announce(1, stealthAddr, hex"01", hex"02");
        }
    }

    // ---- fuzz ----

    /// @notice El evento emitido replica exactamente los parámetros de entrada,
    ///         sin importar el schemeId, la stealth address, el caller ni el
    ///         contenido (largo variable) de ephemeralPubKey/metadata.
    function testFuzz_Announce_EmitsEventWithExactParams(
        uint256 schemeId,
        address stealthAddress,
        address caller,
        bytes memory ephemeralPubKey,
        bytes memory metadata
    ) public {
        vm.assume(caller != address(0));

        vm.expectEmit(true, true, true, true, address(announcer));
        emit IERC5564Announcer.Announcement(schemeId, stealthAddress, caller, ephemeralPubKey, metadata);

        vm.prank(caller);
        announcer.announce(schemeId, stealthAddress, ephemeralPubKey, metadata);
    }
}
