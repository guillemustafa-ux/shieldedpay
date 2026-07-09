pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";

// Prueba de membresía en un árbol de Merkle binario de altura `levels`,
// hasheado con Poseidon(2) en cada nivel. `pathIndices[i]` indica, en el
// nivel i, si el nodo que venimos arrastrando va a la izquierda (0) o a
// la derecha (1) del hermano `pathElements[i]`.
//
// Reutilizado dos veces en withdraw.circom: una contra el árbol de
// depósitos del pool (root) y otra contra el árbol de asociación
// (associationRoot), con el MISMO leaf (commitment) en ambas.
template MerkleTreeInclusionProof(levels) {
    signal input leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal output root;

    component hashers[levels];
    signal levelHashes[levels + 1];
    levelHashes[0] <== leaf;

    signal left[levels];
    signal right[levels];

    for (var i = 0; i < levels; i++) {
        // pathIndices[i] tiene que ser un bit (0 o 1); si no, la constraint
        // no cierra y la prueba es inválida.
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        // Selector sin branching (circom no tiene if real a nivel de
        // constraints): si pathIndices[i]==0, left=levelHashes[i] y
        // right=pathElements[i]; si ==1, se intercambian.
        left[i] <== levelHashes[i] + pathIndices[i] * (pathElements[i] - levelHashes[i]);
        right[i] <== pathElements[i] + pathIndices[i] * (levelHashes[i] - pathElements[i]);

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== left[i];
        hashers[i].inputs[1] <== right[i];
        levelHashes[i + 1] <== hashers[i].out;
    }

    root <== levelHashes[levels];
}
