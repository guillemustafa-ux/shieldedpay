// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ASPRegistry} from "../src/ASPRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ASPRegistry.t — tests del registry multi-ASP (Layer 3 + stub Layer 5)
/// @notice Cubre el ciclo de vida de un ASP: registro con stake, publicación de
///         roots por-ASP (con su historial circular independiente), y el stub de
///         slashing por governance. El invariante clave es que isKnownRoot
///         DISCRIMINA por aspId: una root publicada por el ASP #1 no es válida
///         para el ASP #2.
contract ASPRegistryTest is Test {
    uint256 internal constant MIN_STAKE = 0.01 ether;

    ASPRegistry internal registry;

    address internal governance = makeAddr("governance");
    address internal aspOwner1 = makeAddr("aspOwner1");
    address internal aspOwner2 = makeAddr("aspOwner2");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant POLICY = keccak256("policy-ofac-plus-ronin");
    string internal constant METADATA = "ipfs://policy1";
    bytes32 internal constant DATA_HASH = keccak256("set-data-availability");

    function setUp() public {
        registry = new ASPRegistry(MIN_STAKE, governance);
        vm.deal(aspOwner1, 10 ether);
        vm.deal(aspOwner2, 10 ether);
    }

    // ---------------------------------------------------------------------
    // Registro
    // ---------------------------------------------------------------------

    function test_Register_WithStake_AssignsIdOne() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit ASPRegistry.ASPRegistered(1, aspOwner1, POLICY);

        vm.prank(aspOwner1);
        uint256 aspId = registry.register{value: MIN_STAKE}(POLICY, METADATA);

        assertEq(aspId, 1, "el primer ASP debe tener id 1");
        assertTrue(registry.isActive(1), "el ASP recien registrado debe estar activo");
        assertEq(registry.nextAspId(), 2, "nextAspId debe avanzar a 2");

        (address owner,,, uint256 stake, bool slashed,,,) = registry.asps(1);
        assertEq(owner, aspOwner1, "owner registrado");
        assertEq(stake, MIN_STAKE, "stake guardado");
        assertFalse(slashed, "no slashed al registrarse");
    }

    function test_Register_RevertsIf_StakeInsufficient() public {
        vm.prank(aspOwner1);
        vm.expectRevert("stake insuficiente");
        registry.register{value: MIN_STAKE - 1}(POLICY, METADATA);
    }

    // ---------------------------------------------------------------------
    // publishRoot
    // ---------------------------------------------------------------------

    function test_PublishRoot_ByOwner_RecordsRoot() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);

        uint256 root = 12345;
        vm.expectEmit(true, true, false, true, address(registry));
        emit ASPRegistry.RootPublished(1, root, DATA_HASH);

        vm.prank(aspOwner1);
        registry.publishRoot(1, root, DATA_HASH);

        assertTrue(registry.isKnownRoot(1, root), "la root publicada debe ser conocida");
        (,,,,, uint256 latestRoot, bytes32 latestDataHash,) = registry.asps(1);
        assertEq(latestRoot, root, "latestRoot actualizada");
        assertEq(latestDataHash, DATA_HASH, "latestDataHash actualizado");
    }

    function test_PublishRoot_RevertsIf_NotOwner() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);

        vm.prank(stranger);
        vm.expectRevert("solo el owner del ASP");
        registry.publishRoot(1, 12345, DATA_HASH);
    }

    function test_PublishRoot_RevertsIf_AspInexistent() public {
        vm.prank(aspOwner1);
        vm.expectRevert("ASP inexistente");
        registry.publishRoot(99, 12345, DATA_HASH);
    }

    function test_PublishRoot_RevertsIf_Slashed() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);

        vm.prank(governance);
        registry.slash(1);

        vm.prank(aspOwner1);
        vm.expectRevert("ASP slashed");
        registry.publishRoot(1, 12345, DATA_HASH);
    }

    // ---------------------------------------------------------------------
    // isKnownRoot
    // ---------------------------------------------------------------------

    function test_IsKnownRoot_FalseForUnknownRoot() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);

        vm.prank(aspOwner1);
        registry.publishRoot(1, 12345, DATA_HASH);

        assertFalse(registry.isKnownRoot(1, 99999), "una root nunca publicada no es conocida");
        assertFalse(registry.isKnownRoot(1, 0), "la root 0 nunca es conocida");
    }

    // ---------------------------------------------------------------------
    // Slashing (stub de governance)
    // ---------------------------------------------------------------------

    function test_Slash_MarksInactive() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);
        assertTrue(registry.isActive(1), "activo antes del slash");

        vm.expectEmit(true, false, false, false, address(registry));
        emit ASPRegistry.ASPSlashed(1);

        vm.prank(governance);
        registry.slash(1);

        assertFalse(registry.isActive(1), "inactivo tras el slash");
    }

    function test_Slash_RevertsIf_NotRegistryOwner() public {
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);

        // El owner del ASP NO es el owner del registry: no puede slashear.
        vm.prank(aspOwner1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, aspOwner1));
        registry.slash(1);
    }

    // ---------------------------------------------------------------------
    // Multi-ASP: isKnownRoot discrimina por aspId
    // ---------------------------------------------------------------------

    function test_IsKnownRoot_DiscriminatesByAspId() public {
        // Dos ASPs distintos, cada uno con su propia root.
        vm.prank(aspOwner1);
        registry.register{value: MIN_STAKE}(POLICY, METADATA);
        vm.prank(aspOwner2);
        registry.register{value: MIN_STAKE}(keccak256("policy2"), "ipfs://policy2");

        uint256 root1 = 11111;
        uint256 root2 = 22222;
        vm.prank(aspOwner1);
        registry.publishRoot(1, root1, DATA_HASH);
        vm.prank(aspOwner2);
        registry.publishRoot(2, root2, DATA_HASH);

        // Cada root es conocida SOLO para su propio ASP.
        assertTrue(registry.isKnownRoot(1, root1), "root1 conocida para ASP 1");
        assertTrue(registry.isKnownRoot(2, root2), "root2 conocida para ASP 2");
        assertFalse(registry.isKnownRoot(2, root1), "root1 NO conocida para ASP 2");
        assertFalse(registry.isKnownRoot(1, root2), "root2 NO conocida para ASP 1");
    }
}
