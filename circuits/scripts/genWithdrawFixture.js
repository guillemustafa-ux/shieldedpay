'use strict';

// genWithdrawFixture.js — genera un fixture de retiro VÁLIDO para los tests
// Foundry, con una prueba Groth16 REAL calculada con la wasm+zkey locales.
//
// Por qué un fixture committeado: la .zkey (~9.6MB) y la .wasm están
// gitignoreadas (regenerables, pesadas). En CI no existen, así que no se puede
// generar la prueba ahí. En cambio el fixture JSON es chico y sí se versiona;
// los tests lo leen con vm.readFile/vm.parseJson y verifican una prueba real
// contra el verifier on-chain sin necesitar snarkjs en CI.
//
// El fixture arma el mismo escenario del "caso feliz" de Privacy Pools:
//   - un árbol de ESTADO con N commitments (uno de ellos es "el nuestro"),
//   - un árbol de ASOCIACIÓN (subset limpio) que INCLUYE el nuestro,
//   - la prueba de que nuestro commitment está en ambos, ligada a
//     recipient/relayer/fee de test.
//
// Uso:  node circuits/scripts/genWithdrawFixture.js

const fs = require('node:fs');
const path = require('node:path');
const snarkjs = require('snarkjs');

const {
  buildTree,
  getMerkleProof,
  commitmentOf,
  nullifierHashOf,
  LEVELS,
} = require('../test/merkleTree.js');

const BUILD_DIR = path.join(__dirname, '..', 'build');
const WASM_PATH = path.join(BUILD_DIR, 'withdraw_js', 'withdraw.wasm');
const ZKEY_PATH = path.join(BUILD_DIR, 'withdraw_final.zkey');
const OUT_PATH = path.join(__dirname, '..', '..', 'test', 'fixtures', 'withdraw_valid.json');

// Depósitos de prueba. El de OURS_INDEX es "el nuestro" (el que retiramos).
const DEPOSITS = [
  { nullifier: 111n, secret: 1111n },
  { nullifier: 222n, secret: 2222n }, // <- el nuestro
  { nullifier: 333n, secret: 3333n },
  { nullifier: 444n, secret: 4444n },
];
const OURS_INDEX = 1;

// Valores públicos de test. recipient/relayer son addresses reales (como field
// elements: uint256(uint160(addr))). fee > 0 para ejercitar el pago al relayer.
const RECIPIENT = 0x00000000000000000000000000000000000000A1n;
const RELAYER = 0x00000000000000000000000000000000000000B2n;
const FEE = 1000000000000000n; // 0.001 ETH (< denominación 0.01 ETH)

async function main() {
  if (!fs.existsSync(WASM_PATH) || !fs.existsSync(ZKEY_PATH)) {
    throw new Error(`Faltan artefactos del circuito en ${BUILD_DIR}. Correr el build ZK primero.`);
  }

  const commitments = await Promise.all(DEPOSITS.map((d) => commitmentOf(d.nullifier, d.secret)));
  const stateTree = await buildTree(commitments, LEVELS);

  // Árbol de asociación = subset limpio que incluye el nuestro (indices 0,1,2).
  const assocCommitments = [commitments[0], commitments[1], commitments[2]];
  const assocTree = await buildTree(assocCommitments, LEVELS);

  const own = DEPOSITS[OURS_INDEX];
  const stateProof = getMerkleProof(stateTree, OURS_INDEX);
  const assocProof = getMerkleProof(assocTree, OURS_INDEX); // mismo índice: el subset preserva orden
  const nullifierHash = await nullifierHashOf(own.nullifier);

  const input = {
    nullifier: own.nullifier.toString(),
    secret: own.secret.toString(),
    pathElements: stateProof.pathElements.map(String),
    pathIndices: stateProof.pathIndices.map(String),
    assocPathElements: assocProof.pathElements.map(String),
    assocPathIndices: assocProof.pathIndices.map(String),
    root: stateTree.root.toString(),
    associationRoot: assocTree.root.toString(),
    nullifierHash: nullifierHash.toString(),
    recipient: RECIPIENT.toString(),
    relayer: RELAYER.toString(),
    fee: FEE.toString(),
  };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH);

  // exportSolidityCallData maneja el orden de coordenadas de G2 (que snarkjs
  // invierte respecto de lo que espera el verifier). Parseamos su salida — es
  // "[a0,a1],[[b00,b01],[b10,b11]],[c0,c1],[pub0,...,pub5]" — a arrays limpios.
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const parsed = JSON.parse('[' + calldata + ']');
  const pA = parsed[0];
  const pB = parsed[1];
  const pC = parsed[2];
  const pubSignals = parsed[3];

  const fixture = {
    // Commitments del árbol de estado, EN ORDEN DE INSERCIÓN (los deposita el test).
    commitments: commitments.map(String),
    leafIndex: OURS_INDEX,
    // Señales públicas (para armar el withdraw). El orden del circuito es
    // [root, associationRoot, nullifierHash, recipient, relayer, fee].
    root: stateTree.root.toString(),
    associationRoot: assocTree.root.toString(),
    nullifierHash: nullifierHash.toString(),
    recipient: '0x' + RECIPIENT.toString(16).padStart(40, '0'),
    relayer: '0x' + RELAYER.toString(16).padStart(40, '0'),
    fee: FEE.toString(),
    // Prueba formateada para Solidity (strings decimales/hex que vm.parseJson lee).
    pA,
    pB,
    pC,
    // Redundante con root/associationRoot/... pero útil para sanity-check.
    pubSignals,
  };

  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, JSON.stringify(fixture, null, 2), 'utf8');
  console.error(`[genWithdrawFixture] fixture escrito en ${OUT_PATH}`);
  console.error(`[genWithdrawFixture] root = ${fixture.root}`);
  console.error(`[genWithdrawFixture] associationRoot = ${fixture.associationRoot}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
