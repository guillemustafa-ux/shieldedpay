// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrivacyPoolMultiASP} from "../src/PrivacyPoolMultiASP.sol";
import {ASPRegistry} from "../src/ASPRegistry.sol";
import {FlaggedRegistry} from "../src/FlaggedRegistry.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASPRegistry} from "../src/interfaces/IASPRegistry.sol";
import {IFlaggedRegistry} from "../src/interfaces/IFlaggedRegistry.sol";
import {Groth16Verifier} from "../src/verifiers/WithdrawVerifier.sol";
import {PoseidonDeployer} from "./utils/PoseidonDeployer.sol";

/// @title PrivacyPoolMultiASP.t — end-to-end del pool multi-ASP con prueba ZK REAL
/// @notice Calca test/PrivacyPool.t.sol (mismo fixture, mismo hasher desde
///         bytecode, misma prueba Groth16 auténtica), pero contra el registry
///         descentralizado en vez del ASP single-owner. El corazón del slice es
///         test_Withdraw_ValidProof_AspSelected_PaysRecipient: la MISMA prueba
///         real verifica contra el pool multi-ASP igual que contra el original,
///         probando que el cambio a registry NO tocó la criptografía (aspId es
///         un selector on-chain, no una señal ZK).
contract PrivacyPoolMultiASPTest is Test {
    uint32 internal constant LEVELS = 20;
    uint256 internal constant DENOMINATION = 0.01 ether;
    uint256 internal constant MIN_STAKE = 0.01 ether;

    PrivacyPoolMultiASP internal pool;
    ASPRegistry internal registry;
    IHasher internal hasher;
    Groth16Verifier internal verifier;

    address internal governance = makeAddr("governance");
    address internal aspOwner1 = makeAddr("aspOwner1");
    address internal aspOwner2 = makeAddr("aspOwner2");
    address internal depositor = makeAddr("depositor");

    // ids de los ASPs registrados en setUp.
    uint256 internal aspId1;
    uint256 internal aspId2;

    // --- fixture cargado ---
    uint256[] internal commitments;
    uint256 internal fxRoot;
    uint256 internal fxAssocRoot;
    uint256 internal fxNullifierHash;
    address payable internal fxRecipient;
    address payable internal fxRelayer;
    uint256 internal fxFee;
    uint256[2] internal pA;
    uint256[2][2] internal pB;
    uint256[2] internal pC;

    bytes32 internal constant DATA_HASH = keccak256("set-data-availability");

    function setUp() public {
        hasher = PoseidonDeployer.deploy(vm);
        verifier = new Groth16Verifier();
        // FlaggedRegistry (stub Layer 4): este pool E2E no ejercita el fraud proof de
        // permisividad, pero el ASPRegistry ahora lo exige en su constructor.
        FlaggedRegistry flaggedRegistry = new FlaggedRegistry(governance);
        registry = new ASPRegistry(MIN_STAKE, governance, hasher, IFlaggedRegistry(address(flaggedRegistry)));

        pool = new PrivacyPoolMultiASP(
            IVerifier(address(verifier)), hasher, IASPRegistry(address(registry)), DENOMINATION, LEVELS
        );

        // Registramos 2 ASPs con stake (Layer 3: el usuario podrá elegir).
        vm.deal(aspOwner1, 10 ether);
        vm.deal(aspOwner2, 10 ether);
        vm.prank(aspOwner1);
        aspId1 = registry.register{value: MIN_STAKE}(keccak256("policy1"), "ipfs://policy1");
        vm.prank(aspOwner2);
        aspId2 = registry.register{value: MIN_STAKE}(keccak256("policy2"), "ipfs://policy2");

        _loadFixture();
        vm.deal(depositor, 10 ether);
    }

    /// @dev Carga el fixture JSON con la prueba real y sus señales públicas.
    function _loadFixture() internal {
        string memory json = vm.readFile("test/fixtures/withdraw_valid.json");

        commitments = vm.parseJsonUintArray(json, ".commitments");
        fxRoot = vm.parseJsonUint(json, ".root");
        fxAssocRoot = vm.parseJsonUint(json, ".associationRoot");
        fxNullifierHash = vm.parseJsonUint(json, ".nullifierHash");
        fxRecipient = payable(vm.parseJsonAddress(json, ".recipient"));
        fxRelayer = payable(vm.parseJsonAddress(json, ".relayer"));
        fxFee = vm.parseJsonUint(json, ".fee");

        uint256[] memory a = vm.parseJsonUintArray(json, ".pA");
        pA = [a[0], a[1]];
        uint256[] memory b0 = vm.parseJsonUintArray(json, ".pB[0]");
        uint256[] memory b1 = vm.parseJsonUintArray(json, ".pB[1]");
        pB = [[b0[0], b0[1]], [b1[0], b1[1]]];
        uint256[] memory c = vm.parseJsonUintArray(json, ".pC");
        pC = [c[0], c[1]];
    }

    /// @dev Deposita todos los commitments del fixture, en orden de inserción.
    function _depositAll() internal {
        for (uint256 i = 0; i < commitments.length; i++) {
            vm.prank(depositor);
            pool.deposit{value: DENOMINATION}(commitments[i]);
        }
    }

    /// @dev El ASP #1 publica la association root del fixture (getLastRoot off-chain).
    function _publishAssocRootAsp1() internal {
        vm.prank(aspOwner1);
        registry.publishRoot(aspId1, fxAssocRoot, DATA_HASH);
    }

    // ---------------------------------------------------------------------
    // El corazón del slice: withdraw REAL eligiendo el ASP
    // ---------------------------------------------------------------------

    function test_Withdraw_ValidProof_AspSelected_PaysRecipient() public {
        _depositAll();
        _publishAssocRootAsp1();

        uint256 recipientBefore = fxRecipient.balance;
        uint256 relayerBefore = fxRelayer.balance;
        uint256 poolBefore = address(pool).balance;

        vm.expectEmit(true, true, true, true, address(pool));
        emit PrivacyPoolMultiASP.Withdrawal(fxRecipient, fxNullifierHash, fxRelayer, fxFee);

        // Retiro contra el ASP #1 (el que publicó la root) con la prueba real.
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, aspId1
        );

        assertEq(fxRecipient.balance - recipientBefore, DENOMINATION - fxFee, "recipient cobra denominacion - fee");
        assertEq(fxRelayer.balance - relayerBefore, fxFee, "relayer cobra el fee");
        assertEq(poolBefore - address(pool).balance, DENOMINATION, "el pool paga exactamente una denominacion");
        assertTrue(pool.nullifierHashes(fxNullifierHash), "el nullifierHash queda marcado como gastado");
    }

    // ---------------------------------------------------------------------
    // Rechazos por selección de ASP
    // ---------------------------------------------------------------------

    function test_Withdraw_RevertsIf_AspDidNotPublishRoot() public {
        _depositAll();
        _publishAssocRootAsp1();

        // El ASP #2 existe y está activo, pero NO publicó esta association root.
        vm.expectRevert("ASP inactivo o root desconocida");
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, aspId2
        );
    }

    function test_Withdraw_RevertsIf_AspInexistent() public {
        _depositAll();
        _publishAssocRootAsp1();

        uint256 unknownAspId = 999;
        vm.expectRevert("ASP inactivo o root desconocida");
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, unknownAspId
        );
    }

    function test_Withdraw_RevertsIf_AspSlashed() public {
        _depositAll();
        _publishAssocRootAsp1();

        // Governance slashea al ASP #1: sus roots dejan de servir para retirar.
        vm.prank(governance);
        registry.slash(aspId1);

        vm.expectRevert("ASP inactivo o root desconocida");
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, aspId1
        );
    }

    // ---------------------------------------------------------------------
    // Los invariantes del pool original siguen vigentes
    // ---------------------------------------------------------------------

    function test_Withdraw_RevertsIf_NullifierAlreadySpent() public {
        _depositAll();
        _publishAssocRootAsp1();

        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, aspId1
        );

        vm.expectRevert("nota ya gastada");
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee, aspId1
        );
    }

    function test_Withdraw_RevertsIf_InvalidProof() public {
        _depositAll();
        _publishAssocRootAsp1();

        // Cambiamos el recipient: la prueba estaba ligada a fxRecipient, así que
        // con otra address el array público no matchea y la verificación da false.
        address payable otherRecipient = payable(makeAddr("attacker"));
        vm.expectRevert("prueba invalida");
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, otherRecipient, fxRelayer, fxFee, aspId1
        );
    }

    function test_Withdraw_RevertsIf_FeeWithoutRelayer() public {
        _depositAll();
        _publishAssocRootAsp1();

        // Estado válido (raíz y ASP activo con root publicada, nullifier fresco),
        // pero fee > 0 con relayer == address(0): el guard revierte ANTES de
        // verifyProof, así que no hace falta una prueba ligada a este caso.
        uint256 fee = DENOMINATION / 2;
        vm.expectRevert(bytes("fee > 0 requiere un relayer"));
        pool.withdraw(
            pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, payable(address(0)), fee, aspId1
        );
    }
}
