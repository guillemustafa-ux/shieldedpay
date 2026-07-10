// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ASPRegistry} from "../src/ASPRegistry.sol";
import {FlaggedRegistry} from "../src/FlaggedRegistry.sol";
import {IFlaggedRegistry} from "../src/interfaces/IFlaggedRegistry.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {PoseidonMerkleLib} from "../src/lib/PoseidonMerkleLib.sol";
import {PoseidonDeployer} from "./utils/PoseidonDeployer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ASPRegistry.t — tests del registry multi-ASP (Layer 3 + Layer 5 fraud proof)
/// @notice Cubre el ciclo de vida de un ASP: registro con stake, publicación de
///         roots por-ASP (con su historial circular independiente), el slashing
///         por FRAUD PROOF verificable on-chain (Layer 5) y el slash de
///         emergencia por governance (backup). El invariante clave de Layer 3 es
///         que isKnownRoot DISCRIMINA por aspId. El corazón de Layer 5 es el
///         cross-check: la recomputación on-chain del Merkle root de un set (misma
///         lógica que el harness JS buildTree) coincide bit-a-bit con la root real
///         del fixture, y sobre esa garantía se prueba fraude.
contract ASPRegistryTest is Test {
    uint256 internal constant MIN_STAKE = 0.01 ether;

    ASPRegistry internal registry;
    FlaggedRegistry internal flaggedRegistry;
    IHasher internal hasher;

    address internal governance = makeAddr("governance");
    address internal attester = makeAddr("attester");
    address internal aspOwner1 = makeAddr("aspOwner1");
    address internal aspOwner2 = makeAddr("aspOwner2");
    address internal stranger = makeAddr("stranger");
    address internal challenger = makeAddr("challenger");

    bytes32 internal constant POLICY = keccak256("policy-ofac-plus-ronin");
    string internal constant METADATA = "ipfs://policy1";
    bytes32 internal constant DATA_HASH = keccak256("set-data-availability");

    // Set de asociación del fixture (los 3 primeros commitments) y su root real.
    // El generador (circuits/scripts/genWithdrawFixture.js) arma la association
    // root como buildTree([commitments[0], commitments[1], commitments[2]]).
    uint256[] internal assocSet;
    uint256 internal fxAssocRoot;

    function setUp() public {
        hasher = PoseidonDeployer.deploy(vm);
        flaggedRegistry = new FlaggedRegistry(attester);
        registry = new ASPRegistry(MIN_STAKE, governance, hasher, IFlaggedRegistry(address(flaggedRegistry)));
        vm.deal(aspOwner1, 10 ether);
        vm.deal(aspOwner2, 10 ether);

        // Cargamos el set de asociación del fixture para el cross-check y los
        // fraud proofs (mismo fixture que PrivacyPool/PrivacyPoolMultiASP).
        string memory json = vm.readFile("test/fixtures/withdraw_valid.json");
        uint256[] memory commitments = vm.parseJsonUintArray(json, ".commitments");
        fxAssocRoot = vm.parseJsonUint(json, ".associationRoot");
        assocSet.push(commitments[0]);
        assocSet.push(commitments[1]);
        assocSet.push(commitments[2]);
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
        assertEq(registry.rootDataHash(1, root), DATA_HASH, "rootDataHash comprometido para esa root");
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
    // Slashing de emergencia (governance backup)
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

    // ---------------------------------------------------------------------
    // Layer 5 — Cross-check: recomputación on-chain == root real del fixture
    // ---------------------------------------------------------------------

    /// @notice La recomputación on-chain del Merkle root del set del fixture da
    ///         EXACTAMENTE la associationRoot del fixture. Esta es la garantía que
    ///         hace verificable el fraud proof: la lógica de PoseidonMerkleLib
    ///         replica buildTree (harness JS) bit-a-bit, así que si un ASP publica
    ///         una root != Merkle(set) el contrato lo detecta con certeza.
    function test_ComputeRoot_MatchesFixtureAssociationRoot() public view {
        uint256 recomputed = PoseidonMerkleLib.computeRoot(assocSet, hasher);
        assertEq(recomputed, fxAssocRoot, "root recomputada on-chain == associationRoot del fixture");
    }

    // ---------------------------------------------------------------------
    // Layer 5 — Fraud proof de integridad
    // ---------------------------------------------------------------------

    /// @dev Registra un ASP y lo devuelve. `_dataHash` es el commitment del set.
    function _registerAsp(address owner) internal returns (uint256 aspId) {
        vm.prank(owner);
        aspId = registry.register{value: MIN_STAKE}(POLICY, METADATA);
    }

    function test_ChallengeIntegrity_SlashesLyingAsp_AndRewardsChallenger() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // El ASP MIENTE: publica una root que NO es Merkle(assocSet), pero se
        // compromete (dataHash) al assocSet real.
        uint256 lyingRoot = fxAssocRoot + 1;
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, lyingRoot, dataHash);

        uint256 expectedReward = (MIN_STAKE * registry.SLASH_REWARD_BPS()) / 10000;
        assertEq(challenger.balance, 0, "challenger arranca sin balance");

        vm.expectEmit(true, true, false, true, address(registry));
        emit ASPRegistry.ASPSlashedByFraud(aspId, challenger, expectedReward, "integridad: root != Merkle(set)");

        vm.prank(challenger);
        registry.challengeIntegrity(aspId, lyingRoot, assocSet);

        assertFalse(registry.isActive(aspId), "el ASP queda inactivo tras el slash");
        assertEq(challenger.balance, expectedReward, "el challenger cobra 50% del stake");
        (,,, uint256 stake, bool slashed,,,) = registry.asps(aspId);
        assertTrue(slashed, "slashed == true");
        assertEq(stake, 0, "stake zeroeado tras el slash");
        // El resto del stake queda RETENIDO en el contrato (quemado de facto).
        assertEq(address(registry).balance, MIN_STAKE - expectedReward, "la otra mitad queda retenida");
    }

    function test_ChallengeIntegrity_RevertsIf_HonestAsp() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // ASP HONESTO: publica la root REAL (Merkle(assocSet)) y su dataHash.
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        vm.prank(challenger);
        vm.expectRevert("sin fraude: la root corresponde al set");
        registry.challengeIntegrity(aspId, fxAssocRoot, assocSet);

        assertTrue(registry.isActive(aspId), "un ASP honesto NO es slasheable");
    }

    function test_ChallengeIntegrity_RevertsIf_SetMismatchesDataHash() public {
        uint256 aspId = _registerAsp(aspOwner1);

        uint256 lyingRoot = fxAssocRoot + 1;
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, lyingRoot, dataHash);

        // El challenger intenta framear con un set distinto (keccak != dataHash).
        uint256[] memory fakeSet = new uint256[](2);
        fakeSet[0] = 1;
        fakeSet[1] = 2;

        vm.prank(challenger);
        vm.expectRevert("el set no matchea el dataHash comprometido");
        registry.challengeIntegrity(aspId, lyingRoot, fakeSet);
    }

    function test_ChallengeIntegrity_RevertsIf_RootNotPublished() public {
        uint256 aspId = _registerAsp(aspOwner1);
        // No publicó ninguna root: rootDataHash == 0.
        vm.prank(challenger);
        vm.expectRevert("root no publicada por este ASP");
        registry.challengeIntegrity(aspId, fxAssocRoot, assocSet);
    }

    function test_ChallengeIntegrity_RevertsIf_AlreadySlashed() public {
        uint256 aspId = _registerAsp(aspOwner1);
        uint256 lyingRoot = fxAssocRoot + 1;
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, lyingRoot, dataHash);

        vm.prank(challenger);
        registry.challengeIntegrity(aspId, lyingRoot, assocSet);

        // Segundo challenge sobre el mismo ASP ya slasheado: revierte.
        vm.prank(stranger);
        vm.expectRevert("ASP ya slashed");
        registry.challengeIntegrity(aspId, lyingRoot, assocSet);
    }

    // ---------------------------------------------------------------------
    // Layer 5 — Fraud proof de set degenerado
    // ---------------------------------------------------------------------

    function test_ChallengeDegenerate_SlashesSmallSet_AndRewardsChallenger() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // Set degenerado de tamaño 1 (desanonimiza): un único commitment.
        uint256[] memory tinySet = new uint256[](1);
        tinySet[0] = assocSet[0];
        uint256 degenRoot = PoseidonMerkleLib.computeRoot(tinySet, hasher);
        bytes32 dataHash = keccak256(abi.encodePacked(tinySet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, degenRoot, dataHash);

        uint256 expectedReward = (MIN_STAKE * registry.SLASH_REWARD_BPS()) / 10000;

        vm.expectEmit(true, true, false, true, address(registry));
        emit ASPRegistry.ASPSlashedByFraud(aspId, challenger, expectedReward, "degenerado: set por debajo del minimo");

        vm.prank(challenger);
        registry.challengeDegenerate(aspId, degenRoot, tinySet);

        assertFalse(registry.isActive(aspId), "ASP degenerado queda inactivo");
        assertEq(challenger.balance, expectedReward, "challenger cobra la recompensa");
    }

    function test_ChallengeDegenerate_RevertsIf_SetMeetsMinimum() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // assocSet tiene 3 elementos (>= MIN_SET_SIZE): no es degenerado.
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        vm.prank(challenger);
        vm.expectRevert("sin fraude: el set cumple el tamano minimo");
        registry.challengeDegenerate(aspId, fxAssocRoot, assocSet);

        assertTrue(registry.isActive(aspId), "un ASP con set sano NO es slasheable");
    }

    // ---------------------------------------------------------------------
    // FlaggedRegistry — control de acceso del attester
    // ---------------------------------------------------------------------

    function test_Flag_RevertsIf_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        flaggedRegistry.flag(assocSet[0]);
    }

    function test_Unflag_RevertsIf_NotOwner() public {
        vm.prank(attester);
        flaggedRegistry.flag(assocSet[0]);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        flaggedRegistry.unflag(assocSet[0]);
    }

    function test_FlagUnflag_ByAttester_TogglesState() public {
        assertFalse(flaggedRegistry.isFlagged(assocSet[0]), "arranca limpio");

        vm.prank(attester);
        flaggedRegistry.flag(assocSet[0]);
        assertTrue(flaggedRegistry.isFlagged(assocSet[0]), "marcado tras flag");

        vm.prank(attester);
        flaggedRegistry.unflag(assocSet[0]);
        assertFalse(flaggedRegistry.isFlagged(assocSet[0]), "limpio tras unflag");
    }

    // ---------------------------------------------------------------------
    // Layer 5 — Fraud proof de permisividad (inclusión de un commitment marcado)
    // ---------------------------------------------------------------------

    function test_ChallengeInclusion_SlashesPermissiveAsp_AndRewardsChallenger() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // El ASP publica un set consistente (root == Merkle(set), keccak == dataHash)
        // pero que INCLUYE un commitment que el attester marcó como sucio → permisivo.
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        // El attester marca el commitment del índice 1 del set.
        vm.prank(attester);
        flaggedRegistry.flag(assocSet[1]);

        uint256 expectedReward = (MIN_STAKE * registry.SLASH_REWARD_BPS()) / 10000;
        assertEq(challenger.balance, 0, "challenger arranca sin balance");

        vm.expectEmit(true, true, false, true, address(registry));
        emit ASPRegistry.ASPSlashedByFraud(aspId, challenger, expectedReward, "permisividad: incluyo un commitment marcado");

        vm.prank(challenger);
        registry.challengeInclusion(aspId, fxAssocRoot, assocSet, 1);

        assertFalse(registry.isActive(aspId), "el ASP permisivo queda inactivo tras el slash");
        assertEq(challenger.balance, expectedReward, "el challenger cobra 50% del stake");
        (,,, uint256 stake, bool slashed,,,) = registry.asps(aspId);
        assertTrue(slashed, "slashed == true");
        assertEq(stake, 0, "stake zeroeado tras el slash");
    }

    function test_ChallengeInclusion_RevertsIf_NoFlaggedCommitment() public {
        uint256 aspId = _registerAsp(aspOwner1);

        // Set sin ningún commitment marcado: el attester no marcó nada.
        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        vm.prank(challenger);
        vm.expectRevert("sin fraude: ese commitment no esta marcado");
        registry.challengeInclusion(aspId, fxAssocRoot, assocSet, 1);

        assertTrue(registry.isActive(aspId), "un ASP con set limpio NO es slasheable");
    }

    function test_ChallengeInclusion_RevertsIf_IndexPointsToCleanCommitment() public {
        uint256 aspId = _registerAsp(aspOwner1);

        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        // Se marca el índice 2, pero el challenger apunta al índice 0 (limpio).
        vm.prank(attester);
        flaggedRegistry.flag(assocSet[2]);

        vm.prank(challenger);
        vm.expectRevert("sin fraude: ese commitment no esta marcado");
        registry.challengeInclusion(aspId, fxAssocRoot, assocSet, 0);

        assertTrue(registry.isActive(aspId), "apuntar a un commitment limpio no slashea");
    }

    function test_ChallengeInclusion_RevertsIf_SetMismatchesDataHash() public {
        uint256 aspId = _registerAsp(aspOwner1);

        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        // Aunque marque el commitment, un set cuyo keccak != dataHash no puede framear.
        vm.prank(attester);
        flaggedRegistry.flag(99);

        uint256[] memory fakeSet = new uint256[](2);
        fakeSet[0] = 99;
        fakeSet[1] = 100;

        vm.prank(challenger);
        vm.expectRevert("el set no matchea el dataHash comprometido");
        registry.challengeInclusion(aspId, fxAssocRoot, fakeSet, 0);
    }

    function test_ChallengeInclusion_RevertsIf_IndexOutOfRange() public {
        uint256 aspId = _registerAsp(aspOwner1);

        bytes32 dataHash = keccak256(abi.encodePacked(assocSet));
        vm.prank(aspOwner1);
        registry.publishRoot(aspId, fxAssocRoot, dataHash);

        vm.prank(challenger);
        vm.expectRevert("flaggedIndex fuera de rango");
        registry.challengeInclusion(aspId, fxAssocRoot, assocSet, assocSet.length);
    }

    function test_ChallengeInclusion_RevertsIf_RootNotPublished() public {
        uint256 aspId = _registerAsp(aspOwner1);
        // No publicó ninguna root: rootDataHash == 0.
        vm.prank(challenger);
        vm.expectRevert("root no publicada por este ASP");
        registry.challengeInclusion(aspId, fxAssocRoot, assocSet, 0);
    }
}
