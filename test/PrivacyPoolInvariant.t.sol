// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ASP} from "../src/ASP.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASP} from "../src/interfaces/IASP.sol";
import {Groth16Verifier} from "../src/verifiers/WithdrawVerifier.sol";
import {PoseidonDeployer} from "./utils/PoseidonDeployer.sol";

/// @dev Handler para el invariant. Sólo ejecuta acciones que NO revierten
///      (fail_on_revert = true en foundry.toml):
///
///        - deposit(): siempre deposita un commitment FRESCO (derivado de un
///          nonce monótono, nunca colisiona con uno previo) por exactamente la
///          denominación, y cuenta el depósito en un ghost.
///        - withdraw(): ejecuta el ÚNICO retiro válido del que tenemos prueba
///          real (el del fixture) a lo sumo una vez, y sólo si su raíz de estado
///          sigue viva en el historial. Si ya se hizo o la raíz rotó fuera de la
///          ventana, no hace nada (return temprano) — así nunca revierte.
///
///      El ghost (depositCount, withdrawCount) es el oráculo independiente que
///      el invariant compara contra el balance real del pool.
contract PrivacyPoolHandler is Test {
    PrivacyPool public pool;
    ASP public asp;
    uint256 public constant DENOMINATION = 0.01 ether;

    uint256 public depositCount;
    uint256 public withdrawCount;
    uint256 internal depositNonce;

    bool internal withdrawn;

    // fixture
    uint256[] internal fixtureCommitments;
    uint256 internal fxRoot;
    uint256 internal fxAssocRoot;
    uint256 internal fxNullifierHash;
    address payable internal fxRecipient;
    address payable internal fxRelayer;
    uint256 internal fxFee;
    uint256[2] internal pA;
    uint256[2][2] internal pB;
    uint256[2] internal pC;

    constructor(PrivacyPool _pool, ASP _asp) {
        pool = _pool;
        asp = _asp;
        _loadFixture();
    }

    function _loadFixture() internal {
        string memory json = vm.readFile("test/fixtures/withdraw_valid.json");
        fixtureCommitments = vm.parseJsonUintArray(json, ".commitments");
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

    /// @dev Semilla determinista (la corre setUp una vez): deposita los 4
    ///      commitments del fixture (para que fxRoot exista) y publica su
    ///      associationRoot. Deja el escenario listo para un retiro real.
    function seed() external {
        for (uint256 i = 0; i < fixtureCommitments.length; i++) {
            pool.deposit{value: DENOMINATION}(fixtureCommitments[i]);
            depositCount++;
        }
        asp.publishAssociationRoot(fxAssocRoot);
    }

    function deposit(uint256) external {
        // Commitment fresco: keccak de un nonce monótono, mod campo BN254.
        uint256 c = uint256(keccak256(abi.encode("invariantDeposit", depositNonce))) % pool.FIELD_SIZE();
        depositNonce++;
        if (c == 0 || pool.commitments(c)) return; // guarda anti-revert (colisión ~imposible)
        pool.deposit{value: DENOMINATION}(c);
        depositCount++;
    }

    function withdraw(uint256) external {
        if (withdrawn) return;
        if (!pool.isKnownRoot(fxRoot)) return; // la raíz rotó fuera del historial
        withdrawn = true;
        withdrawCount++;
        pool.withdraw(pA, pB, pC, fxRoot, fxAssocRoot, fxNullifierHash, fxRecipient, fxRelayer, fxFee);
    }

    receive() external payable {}
}

/// @title Invariant — PrivacyPool: el balance custodiado siempre cuadra
/// @notice Propiedad contable central de un mixer de denominación fija: el ETH
///         que el pool custodia es EXACTAMENTE la denominación por cada depósito
///         que todavía no fue retirado. Ni se crea ni se pierde valor.
contract PrivacyPoolInvariantTest is StdInvariant, Test {
    PrivacyPool internal pool;
    ASP internal asp;
    IHasher internal hasher;
    Groth16Verifier internal verifier;
    PrivacyPoolHandler internal handler;

    uint256 internal constant DENOMINATION = 0.01 ether;

    function setUp() public {
        hasher = PoseidonDeployer.deploy(vm);
        verifier = new Groth16Verifier();

        // El handler es el owner del ASP (para poder publicar raíces) y el
        // depositante; le damos fondos de sobra para toda la campaña.
        asp = new ASP(address(this));
        pool = new PrivacyPool(IVerifier(address(verifier)), hasher, IASP(address(asp)), DENOMINATION, 20);

        handler = new PrivacyPoolHandler(pool, asp);
        asp.transferOwnership(address(handler));
        vm.deal(address(handler), 100_000 ether);

        handler.seed();

        // Sólo el handler es objetivo del fuzzer, y sólo sus funciones
        // deposit/withdraw (seed() ya corrió acá y no debe re-ejecutarse).
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PrivacyPoolHandler.deposit.selector;
        selectors[1] = PrivacyPoolHandler.withdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_PoolBalanceEqualsUnspentDeposits() public view {
        uint256 expected = DENOMINATION * (handler.depositCount() - handler.withdrawCount());
        assertEq(address(pool).balance, expected, "el balance del pool debe ser denominacion * (depositos - retiros)");
    }
}
