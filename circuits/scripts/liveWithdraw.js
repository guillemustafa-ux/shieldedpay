'use strict';

// liveWithdraw.js — genera la prueba Groth16 de retiro para una de las notas
// de demo sembradas por SeedDemo.s.sol y la imprime como comando `cast send`
// listo para ejecutar contra el pool REAL en Sepolia.
//
// Es la verificación end-to-end del deploy: si este retiro paga, todo el
// pipeline (árbol on-chain == árbol local, ASP root, verifier, binding de
// señales) está probado en vivo, no solo en tests.
//
// Supuesto deliberado: el pool está RECIÉN sembrado, así que el árbol de
// estado local se reconstruye con las 3 notas de demo en orden de inserción.
// Si el pool ya recibió depósitos de terceros, reconstruir el árbol requiere
// leer los eventos Deposit (eso lo hace la dApp; este script es para el
// smoke-test post-deploy).
//
// Uso:
//   NOTE_INDEX=0 RECIPIENT=0x... node circuits/scripts/liveWithdraw.js

const fs = require('node:fs');
const path = require('node:path');
const snarkjs = require('snarkjs');

const { buildTree, getMerkleProof, commitmentOf, nullifierHashOf, LEVELS } = require('../test/merkleTree.js');

const BUILD_DIR = path.join(__dirname, '..', 'build');
const WASM_PATH = path.join(BUILD_DIR, 'withdraw_js', 'withdraw.wasm');
const ZKEY_PATH = path.join(BUILD_DIR, 'withdraw_final.zkey');

// Las 3 notas públicas de demo (las mismas de SeedDemo.s.sol y el README).
const DEMO_DEPOSITS = [
  { nullifier: 1n, secret: 11n },
  { nullifier: 2n, secret: 22n },
  { nullifier: 3n, secret: 33n },
];

async function main() {
  if (!fs.existsSync(WASM_PATH) || !fs.existsSync(ZKEY_PATH)) {
    throw new Error(`Faltan artefactos ZK en ${BUILD_DIR}. Ver circuits/README para regenerarlos.`);
  }
  const noteIndex = Number(process.env.NOTE_INDEX ?? '0');
  const recipient = (process.env.RECIPIENT ?? '').trim();
  if (!/^0x[0-9a-fA-F]{40}$/.test(recipient)) {
    throw new Error('RECIPIENT inválido: pasá una address 0x... por env.');
  }
  const own = DEMO_DEPOSITS[noteIndex];
  if (!own) throw new Error(`NOTE_INDEX fuera de rango (0..${DEMO_DEPOSITS.length - 1}).`);

  const commitments = await Promise.all(DEMO_DEPOSITS.map((d) => commitmentOf(d.nullifier, d.secret)));
  const stateTree = await buildTree(commitments, LEVELS);
  // SeedDemo publica como set de asociación el MISMO conjunto de 3 depósitos.
  const assocTree = await buildTree(commitments, LEVELS);

  const stateProof = getMerkleProof(stateTree, noteIndex);
  const assocProof = getMerkleProof(assocTree, noteIndex);
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
    recipient: BigInt(recipient).toString(),
    relayer: '0',
    fee: '0',
  };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH);
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [pA, pB, pC] = JSON.parse('[' + calldata + ']');

  const fmt = (arr) => '[' + arr.map(String).join(',') + ']';
  const pBFlat = '[' + pB.map((pair) => fmt(pair)).join(',') + ']';

  console.log('root:            ', stateTree.root.toString());
  console.log('associationRoot: ', assocTree.root.toString());
  console.log('nullifierHash:   ', nullifierHash.toString());
  console.log('');
  console.log('# Comando listo (completar POOL y RPC):');
  console.log(
    `cast send $POOL "withdraw(uint256[2],uint256[2][2],uint256[2],uint256,uint256,uint256,address,address,uint256)" ` +
      `"${fmt(pA)}" "${pBFlat}" "${fmt(pC)}" ` +
      `${stateTree.root} ${assocTree.root} ${nullifierHash} ${recipient} 0x0000000000000000000000000000000000000000 0 ` +
      `--rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY`,
  );
  process.exit(0); // el pool de workers de snarkjs cuelga el proceso sin esto
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
