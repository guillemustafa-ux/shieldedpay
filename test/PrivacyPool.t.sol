// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ASP} from "../src/ASP.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASP} from "../src/interfaces/IASP.sol";
import {Groth16Verifier} from "../src/verifiers/WithdrawVerifier.sol";
import {PoseidonDeployer} from "./utils/PoseidonDeployer.sol";

/// @title PrivacyPool.t — tests del pool con una prueba ZK REAL
/// @notice El corazón de estos tests es el cross-check del hasher: si el
///         Poseidon on-chain no matcheara circomlibjs, `getLastRoot()` no
///         coincidiría con el root del harness JS y la prueba real no
///         verificaría. Cargamos un fixture (test/fixtures/withdraw_valid.json)
///         generado por circuits/scripts/genWithdrawFixture.js con una prueba
///         Groth16 auténtica.
contract PrivacyPoolTest is Test {
    uint32 internal constant LEVELS = 20;
    uint256 internal constant DENOMINATION = 0.01 ether;

    PrivacyPool internal pool;
    ASP internal asp;
    IHasher internal hasher;
    Groth16Verifier internal verifier;

    address internal owner = makeAddr("owner");
    address internal depositor = makeAddr("depositor");

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

    function setUp() public {
        // Hasher Poseidon(2) desde bytecode circomlibjs, verifier y ASP.
        hasher = PoseidonDeployer.deploy(vm);
        verifier = new Groth16Verifier();
        asp = new ASP(owner);

        pool = new PrivacyPool(IVerifier(address(verifier)), hasher, IASP(address(asp)), DENOMINATION, LEVELS);

        _loadFixture();

        // Fondos para el depositante (4 depósitos + margen).
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

    // ---------------------------------------------------------------------
    // Cross-check crítico: raíz on-chain == raíz del harness JS
    // ---------------------------------------------------------------------

    function test_MerkleRoot_MatchesJsHarness() public {
        _depositAll();
        assertEq(
            pool.getLastRoot(),
            fxRoot,
            "la raiz on-chain (Poseidon) debe coincidir con la del harness JS/circuito"
        );
        assertTrue(pool.isKnownRoot(fxRoot), "la raiz del fixture debe estar en el historial");
    }

    // ---------------------------------------------------------------------
    // Depósitos
    // ---------------------------------------------------------------------

    function test_Deposit_InsertsAndEmits() public {
        vm.expectEmit(true, false, false, false, address(pool));
        emit PrivacyPool.Deposit(commitments[0], 0, block.timestamp);

        vm.prank(depositor);
        pool.deposit{value: DENOMINATION}(commitments[0]);

        assertTrue(pool.commitments(commitments[0]), "el commitment debe quedar registrado");
        assertEq(pool.nextIndex(), 1, "nextIndex debe avanzar a 1");
        assertEq(address(pool).balance, DENOMINATION, "el pool debe custodiar la denominacion");
    }

    function test_Deposit_RevertsIf_WrongValue() public {
        vm.prank(depositor);
        vm.expectRevert("el monto debe ser la denominacion exacta");
        pool.deposit{value: DENOMINATION - 1}(commitments[0]);
    }

    function test_Deposit_RevertsIf_DuplicateCommitment() public {
        vm.prank(depositor);
        pool.deposit{value: DENOMINATION}(commitments[0]);

        vm.prank(depositor);
        vm.expectRevert("commitment ya depositado");
        pool.deposit{value: DENOMINATION}(commitments[0]);
    }

    // ---------------------------------------------------------------------
    // Retiro con prueba REAL
    // ---------------------------------------------------------------------

    function test_Withdraw_ValidProof_PaysRecipient() public {
        _depositAll();
        vm.prank(owner);
        asp.publishAssociationRoot(fxAssocRoot);

        uint256 recipientBefore = fxRecipient.balance;
        uint256 relayerBefore = fxRelayer.balance;
        uint256 poolBefore = address(pool).balance;

        vm.expectEmit(true, true, true, true, address(pool));
        emit PrivacyPool.Withdrawal(fxRecipient, fxNullifierHash, fxRelayer, fxFee);

        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);

        assertEq(fxRecipient.balance - recipientBefore, DENOMINATION - fxFee, "recipient cobra denominacion - fee");
        assertEq(fxRelayer.balance - relayerBefore, fxFee, "relayer cobra el fee");
        assertEq(poolBefore - address(pool).balance, DENOMINATION, "el pool paga exactamente una denominacion");
        assertTrue(pool.nullifierHashes(fxNullifierHash), "el nullifierHash queda marcado como gastado");
    }

    function test_Withdraw_RevertsIf_NullifierAlreadySpent() public {
        _depositAll();
        vm.prank(owner);
        asp.publishAssociationRoot(fxAssocRoot);

        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);

        vm.expectRevert("nota ya gastada");
        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);
    }

    function test_Withdraw_RevertsIf_InvalidProof() public {
        _depositAll();
        vm.prank(owner);
        asp.publishAssociationRoot(fxAssocRoot);

        // Cambiamos el recipient: la prueba estaba ligada a fxRecipient, así que
        // con otra address el array público no matchea y la verificación da false.
        address payable otherRecipient = payable(makeAddr("attacker"));
        vm.expectRevert("prueba invalida");
        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, otherRecipient, fxRelayer, fxFee);
    }

    function test_Withdraw_RevertsIf_AssociationRootNotPublished() public {
        _depositAll();
        // Deliberadamente NO publicamos la associationRoot en el ASP: un depósito
        // fuera del set limpio no puede retirar. Este es el núcleo del compliance.
        vm.expectRevert("association root no publicada por el ASP");
        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);
    }

    function test_Withdraw_RevertsIf_UnknownStateRoot() public {
        _depositAll();
        vm.prank(owner);
        asp.publishAssociationRoot(fxAssocRoot);

        uint256 bogusRoot = fxRoot + 1; // no está en el historial
        vm.expectRevert("raiz de estado desconocida");
        pool.withdraw(pA, pB, pC, bogusRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);
    }

    function test_Withdraw_RevertsIf_FeeExceedsDenomination() public {
        _depositAll();
        vm.prank(owner);
        asp.publishAssociationRoot(fxAssocRoot);

        uint256 tooMuch = DENOMINATION + 1;
        vm.expectRevert("el fee no puede superar la denominacion");
        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, tooMuch);
    }
}
