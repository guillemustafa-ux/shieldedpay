// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHasher} from "../interfaces/IHasher.sol";

/// @title PoseidonMerkleLib — recomputación on-chain del sparse Merkle root (Poseidon)
/// @notice Replica EXACTAMENTE la función `buildTree` de circuits/test/merkleTree.js:
///         dado un array de hojas (en orden de inserción), construye el árbol
///         incremental/sparse de altura fija `LEVELS` (=20) nivel por nivel,
///         hasheando pares con Poseidon(2). Cuando un nivel tiene una cantidad
///         impar de nodos, el hermano faltante del último par es `zeros(level)`
///         (el hash del subárbol vacío de esa altura). El resultado es, bit-a-bit,
///         la misma root que produce el harness JS y que el árbol on-chain
///         (MerkleTreeWithHistory), de modo que se puede usar como testigo dentro
///         de un fraud proof: si la root recomputada del set NO coincide con la que
///         un ASP publicó, el ASP mintió.
///
/// @dev Los 21 valores de `zeros` están hardcodeados (idénticos a
///      MerkleTreeWithHistory.zeros() y a computeZeros(20) del harness) para
///      garantizar coincidencia exacta y no recalcular Poseidon en cada challenge.
///      Es una `library` con funciones `internal`: se inlinea en el contrato que
///      la usa (el registry al validar el challenge, o el test al hacer el
///      cross-check), sin necesidad de deployarla por separado.
library PoseidonMerkleLib {
    /// @notice Campo escalar de BN254 (mismo que MerkleTreeWithHistory).
    uint256 internal constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Altura del árbol (igual que el pool y el circuito).
    uint32 internal constant LEVELS = 20;

    /// @notice zeros(i) = hash del subárbol vacío de altura `i`.
    /// @dev Copia textual de MerkleTreeWithHistory.zeros() (misma derivación
    ///      "nothing-up-my-sleeve": zeros[0] = keccak256("shieldedpay") mod p,
    ///      zeros[i] = Poseidon(zeros[i-1], zeros[i-1])). Se replica acá para que
    ///      la lib sea autocontenida y reusable sin heredar del árbol.
    function zeros(uint256 i) internal pure returns (uint256) {
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

    /// @notice Recomputa el sparse Merkle root de `leaves` con `hasher`.
    /// @dev Réplica 1:1 de buildTree(leaves, 20):
    ///        - por cada nivel 0..19 se colapsa el array actual a la mitad
    ///          (redondeando hacia arriba): cada par (left, right) se hashea con
    ///          Poseidon(2); si el nivel tiene cantidad impar de nodos, el `right`
    ///          del último par es zeros(level).
    ///        - la root es el único nodo que queda tras 20 niveles (para
    ///          leaves.length <= 2^20); un set vacío recompone a zeros(20).
    ///      COSTE: O(leaves.length + LEVELS) hashes Poseidon. Viable para sets
    ///      chicos; caro para sets grandes (ver nota de escalabilidad en el
    ///      registry). Exige que cada hoja esté en el campo (misma precondición
    ///      que MerkleTreeWithHistory.hashLeftRight).
    /// @param leaves Hojas del set, en orden de inserción.
    /// @param hasher Hasher Poseidon(2) on-chain.
    /// @return root Root recomputada.
    function computeRoot(uint256[] memory leaves, IHasher hasher) internal pure returns (uint256 root) {
        uint256 len = leaves.length;
        if (len == 0) return zeros(LEVELS);

        uint256[] memory current = leaves;
        for (uint32 level = 0; level < LEVELS; level++) {
            uint256 z = zeros(level);
            uint256 nextLen = (len + 1) / 2;
            uint256[] memory next = new uint256[](nextLen);
            for (uint256 i = 0; i < len; i += 2) {
                uint256 left = current[i];
                uint256 right = (i + 1 < len) ? current[i + 1] : z;
                require(left < FIELD_SIZE, "hoja izquierda fuera del campo");
                require(right < FIELD_SIZE, "hoja derecha fuera del campo");
                uint256[2] memory input;
                input[0] = left;
                input[1] = right;
                next[i / 2] = hasher.poseidon(input);
            }
            current = next;
            len = nextLen;
        }
        return current[0];
    }
}
