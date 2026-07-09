// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHasher} from "./interfaces/IHasher.sol";

/// @title MerkleTreeWithHistory — árbol de Merkle incremental con historial de raíces (Poseidon)
/// @notice Port del `MerkleTreeWithHistory` de Tornado Cash pero hasheando con
///         Poseidon(2) en lugar de MiMC, para que las raíces coincidan con las
///         que prueba el circuito withdraw.circom (que usa Poseidon).
///
///         Es un árbol "incremental / sparse" de altura fija `levels` (=20):
///         nunca materializa las 2^20 hojas; sólo mantiene, por nivel, el
///         subárbol izquierdo ya lleno (`filledSubtrees`) y reusa el hash de un
///         subárbol vacío (`zeros(i)`) para todo lo que aún no se insertó. Es
///         EXACTAMENTE el mismo algoritmo que circuits/test/merkleTree.js
///         (buildTree), de modo que insertar los mismos commitments en el mismo
///         orden produce la misma raíz on-chain que off-chain. Ese cross-check
///         está testeado en test/PrivacyPool.t.sol (test_MerkleRoot_MatchesJsHarness).
///
/// @dev Guardamos un historial circular de las últimas ROOT_HISTORY_SIZE raíces
///      para que un retiro pueda referirse a una raíz reciente aunque hayan
///      entrado depósitos nuevos entre que el usuario armó la prueba y la envió.
contract MerkleTreeWithHistory {
    /// @notice Campo escalar de BN254 (el que usan snarkjs/circom por defecto).
    uint256 public constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Hoja vacía: keccak256("shieldedpay") mod FIELD_SIZE (ver
    ///         circuits/test/merkleTree.js). "Nothing-up-my-sleeve", igual que
    ///         el ZERO_VALUE de Tornado.
    uint256 public constant ZERO_VALUE =
        9880778443085210058860878218881645598704289061394908001763061260920381531404;

    /// @notice Cantidad de raíces históricas que recordamos (ventana circular).
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    /// @notice Altura del árbol (cantidad de niveles). Fijado en 20 por el pool.
    uint32 public immutable levels;

    /// @notice Hasher Poseidon(2) on-chain (deployado desde bytecode de circomlibjs).
    IHasher public immutable hasher;

    /// @notice Por nivel `i`, el hash del subárbol izquierdo ya completado.
    mapping(uint256 => uint256) public filledSubtrees;

    /// @notice Historial circular de raíces: índice => raíz.
    mapping(uint256 => uint256) public roots;

    /// @notice Índice (en `roots`) de la raíz vigente.
    uint32 public currentRootIndex;

    /// @notice Próximo índice de hoja libre (cuántos depósitos se insertaron).
    uint32 public nextIndex;

    /// @param _levels Altura del árbol (el pool pasa 20).
    /// @param _hasher Hasher Poseidon(2) on-chain.
    constructor(uint32 _levels, IHasher _hasher) {
        require(_levels > 0, "levels debe ser > 0");
        require(_levels < 32, "levels demasiado grande");
        levels = _levels;
        hasher = _hasher;

        // Inicializamos cada filledSubtree con el subárbol vacío de su nivel y
        // sembramos la raíz inicial (árbol totalmente vacío) en el historial.
        for (uint32 i = 0; i < _levels; i++) {
            filledSubtrees[i] = zeros(i);
        }
        roots[0] = zeros(_levels);
    }

    /// @notice Hash de dos hijos con Poseidon(2). Exige que ambos estén en el
    ///         campo (misma precondición que el circuito).
    function hashLeftRight(uint256 left, uint256 right) public view returns (uint256) {
        require(left < FIELD_SIZE, "left fuera del campo");
        require(right < FIELD_SIZE, "right fuera del campo");
        uint256[2] memory input;
        input[0] = left;
        input[1] = right;
        return hasher.poseidon(input);
    }

    /// @notice Inserta una hoja (commitment) y actualiza el historial de raíces.
    /// @dev Algoritmo incremental estándar: subimos desde la hoja hacia la raíz;
    ///      en cada nivel, si estamos en un índice par (hijo izquierdo) el
    ///      hermano derecho todavía es un subárbol vacío y guardamos el nodo
    ///      actual como `filledSubtrees[i]`; si es impar (hijo derecho) el
    ///      hermano izquierdo es el `filledSubtrees[i]` guardado antes.
    /// @param leaf Commitment a insertar.
    /// @return index Índice de la hoja recién insertada.
    function _insert(uint256 leaf) internal returns (uint32 index) {
        uint32 _nextIndex = nextIndex;
        require(_nextIndex != uint32(2) ** levels, "el arbol de Merkle esta lleno");

        uint32 currentIndex = _nextIndex;
        uint256 currentLevelHash = leaf;
        uint256 left;
        uint256 right;

        for (uint32 i = 0; i < levels; i++) {
            if (currentIndex % 2 == 0) {
                left = currentLevelHash;
                right = zeros(i);
                filledSubtrees[i] = currentLevelHash;
            } else {
                left = filledSubtrees[i];
                right = currentLevelHash;
            }
            currentLevelHash = hashLeftRight(left, right);
            currentIndex /= 2;
        }

        uint32 newRootIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        currentRootIndex = newRootIndex;
        roots[newRootIndex] = currentLevelHash;
        nextIndex = _nextIndex + 1;
        return _nextIndex;
    }

    /// @notice ¿`root` está en el historial circular de raíces recientes?
    /// @dev Recorre desde la raíz vigente hacia atrás; ignora el valor 0
    ///      (slots aún no escritos).
    function isKnownRoot(uint256 root) public view returns (bool) {
        if (root == 0) return false;
        uint32 _currentRootIndex = currentRootIndex;
        uint32 i = _currentRootIndex;
        do {
            if (root == roots[i]) return true;
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != _currentRootIndex);
        return false;
    }

    /// @notice Raíz vigente del árbol.
    function getLastRoot() public view returns (uint256) {
        return roots[currentRootIndex];
    }

    /// @notice zeros(i) = hash del subárbol vacío de altura `i`.
    /// @dev Valores precomputados con circuits/scripts/genPoseidon.js (que a su
    ///      vez usa computeZeros(20) de merkleTree.js): zeros[0] = ZERO_VALUE,
    ///      zeros[i] = Poseidon(zeros[i-1], zeros[i-1]). Hardcodeados (patrón
    ///      Tornado) para no recalcular Poseidon 20 veces en el constructor y,
    ///      sobre todo, para garantizar que coincidan EXACTAMENTE con el harness.
    function zeros(uint256 i) public pure returns (uint256) {
        if (i == 0) return 9880778443085210058860878218881645598704289061394908001763061260920381531404;
        if (i == 1) return 15259115992093359057306612732202112088486866570850663523687003542374167458490;
        if (i == 2) return 2042315549721058920637008987003837273472692319536832204153007114081621773735;
        if (i == 3) return 13650026916254236523664281207298881841519782524061753524924611662892498768710;
        if (i == 4) return 11485300474476156175644568481249642487609403115754877552547729118735105293428;
        if (i == 5) return 1273607262036541994778548352487586338232204983008962358925153656207409068215;
        if (i == 6) return 12528788329791230913702346232126666765927984571126940463881879737270950698920;
        if (i == 7) return 8440637985273327200353625852773112593891940677640081556911932552715278446287;
        if (i == 8) return 13638492303818173535494070933104567083705804879866424504623800463516200012131;
        if (i == 9) return 17524320047406027140926599433579401602714818386567206825930587310040261356669;
        if (i == 10) return 17354560219187958264973157045152938707553262119320508678710979941535332806876;
        if (i == 11) return 9636213539427939110412916866436268440445606778203414053653667588825565214290;
        if (i == 12) return 8895874972800181056498282355622922778812511756679079894342771350055753161084;
        if (i == 13) return 11737713223592627329703045664537379846325649844809123435067652852790898605108;
        if (i == 14) return 4545100119790611053937865702004313408095973556112304964661313627516804092491;
        if (i == 15) return 4654044917498092750692639126265342757848938777821805355316804362789730628273;
        if (i == 16) return 20342386871760394720527733276056131119870811305418271433376918470212826718423;
        if (i == 17) return 12066760983559033436607792541141168824935355570253998076636557545670830029465;
        if (i == 18) return 748578875903578844006317597892571945373796467143942383757847050344404966119;
        if (i == 19) return 18310403454227330793311974976917646803646175964408489801331971142700579749423;
        if (i == 20) return 14483859456517795300232703368134329049844095251594817375522134617172646571524;
        revert("indice de zeros fuera de rango");
    }
}
