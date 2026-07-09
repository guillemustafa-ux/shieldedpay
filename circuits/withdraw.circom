pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "lib/merkleProof.circom";

// ShieldedPay — circuito de retiro (Privacy Pool con association set)
//
// Prueba, SIN revelar cuál de los depósitos del pool es el propio, que
// quien retira:
//
//   1) conoce un (nullifier, secret) tales que
//      commitment = Poseidon(nullifier, secret)  — el "recibo" que se
//      publicó on-chain al depositar.
//
//   2) ese commitment pertenece al árbol de TODOS los depósitos del pool
//      (root) — prueba de membresía estándar (como Tornado Cash).
//
//   3) ese MISMO commitment pertenece TAMBIÉN al árbol de asociación
//      (associationRoot) — el subconjunto de depósitos que el ASP
//      (Association Set Provider) declaró "limpios" en algún momento.
//      Este es el mecanismo de Privacy Pools (Buterin/Illum/Nadler/Schär
//      2023): quien retira demuestra pertenencia al set limpio sin
//      revelar cuál es su depósito. Si tu depósito viene de una fuente
//      marcada, el ASP nunca lo incluyó en este árbol y esta prueba no
//      cierra — no hay forma de falsearla sin el path real.
//
//   4) nullifierHash = Poseidon(nullifier) es público: el contrato lo
//      marca como gastado para evitar retirar el mismo depósito dos
//      veces, sin que el hash revele qué nullifier (y por lo tanto qué
//      commitment) le corresponde.
//
//   5) recipient/relayer/fee quedan ligados a la prueba: un relayer
//      deshonesto no puede reescribir a dónde van los fondos después de
//      recibir la prueba, porque cualquier cambio en estos valores
//      públicos invalida la verificación (forman parte del hash público
//      que Groth16 verifica on-chain). El truco `xSquare <== x*x` es lo
//      que exige el compilador de circom para que una señal pública que
//      no participa de ningún otro cómputo igual quede atada a al menos
//      una constraint (si no, circom la rechaza como "unused"). Es el
//      mismo patrón que usa Tornado Cash — no aporta nada criptográfico
//      más allá de forzar el binding, pero es necesario por eso.
//
// `levels` = altura de AMBOS árboles (estado y asociación). Fijado en 20
// más abajo (component main): mismo orden de magnitud que Tornado Cash
// clásico (2^20 ≈ 1M hojas posibles), un valor reconocible para cualquiera
// que ya conozca ese diseño.
template Withdraw(levels) {
    // ---- privados: el "secreto" del depósito propio ----
    signal input nullifier;
    signal input secret;

    // ---- privados: el path de Merkle hacia el árbol de estado ----
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // ---- privados: el path de Merkle hacia el árbol de asociación ----
    signal input assocPathElements[levels];
    signal input assocPathIndices[levels];

    // ---- públicos ----
    signal input root;             // raíz vigente del árbol de depósitos del pool
    signal input associationRoot;  // raíz vigente del árbol de asociación (ASP)
    signal input nullifierHash;    // Poseidon(nullifier), para marcar como gastado
    signal input recipient;        // address destino de los fondos (as field element)
    signal input relayer;          // address del relayer (0 si retira uno mismo)
    signal input fee;              // fee para el relayer, en wei

    // 1) commitment = Poseidon(nullifier, secret)
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== nullifier;
    commitmentHasher.inputs[1] <== secret;
    signal commitment;
    commitment <== commitmentHasher.out;

    // 4) nullifierHash = Poseidon(nullifier) — se compara contra el input público
    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;
    nullifierHash === nullifierHasher.out;

    // 2) membership en el árbol de depósitos del pool
    component stateProof = MerkleTreeInclusionProof(levels);
    stateProof.leaf <== commitment;
    for (var i = 0; i < levels; i++) {
        stateProof.pathElements[i] <== pathElements[i];
        stateProof.pathIndices[i] <== pathIndices[i];
    }
    root === stateProof.root;

    // 3) membership del MISMO commitment en el árbol de asociación (ASP)
    component assocProof = MerkleTreeInclusionProof(levels);
    assocProof.leaf <== commitment;
    for (var i = 0; i < levels; i++) {
        assocProof.pathElements[i] <== assocPathElements[i];
        assocProof.pathIndices[i] <== assocPathIndices[i];
    }
    associationRoot === assocProof.root;

    // 5) binding anti-tampering de recipient/relayer/fee (ver nota arriba)
    signal recipientSquare;
    signal relayerSquare;
    signal feeSquare;
    recipientSquare <== recipient * recipient;
    relayerSquare <== relayer * relayer;
    feeSquare <== fee * fee;
}

component main {public [root, associationRoot, nullifierHash, recipient, relayer, fee]} = Withdraw(20);
