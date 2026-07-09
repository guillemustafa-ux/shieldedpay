'use strict';

// Tests de circuito para withdraw.circom (Fase B, D2 del PLAN.md).
//
// Un caso valido + tres casos invalidos que representan, cada uno, un
// intento de romper alguna de las 4 garantias que el circuito promete
// (ver comentario de cabecera de circuits/withdraw.circom):
//   1) conocer (nullifier, secret) del propio commitment
//   2) membresia en el arbol de estado (todos los depositos del pool)
//   3) membresia del MISMO commitment en el arbol de asociacion (ASP)
//   4) nullifierHash = Poseidon(nullifier) coherente
//
// snarkjs.groth16.fullProve calcula el witness ejecutando el circuito
// compilado (.wasm); si alguna constraint no cierra, el calculo del
// witness tira un error y la promesa rechaza — eso es lo que usamos para
// afirmar "prueba invalida no se puede generar" en los casos 2-4.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const snarkjs = require('snarkjs');

const {
  buildTree,
  getMerkleProof,
  commitmentOf,
  nullifierHashOf,
  LEVELS,
} = require('./merkleTree.js');

const BUILD_DIR = path.join(__dirname, '..', 'build');
const WASM_PATH = path.join(BUILD_DIR, 'withdraw_js', 'withdraw.wasm');
const ZKEY_PATH = path.join(BUILD_DIR, 'withdraw_final.zkey');
const VKEY_PATH = path.join(BUILD_DIR, 'verification_key.json');

// Fixture compartido: 4 depositos de prueba. El deposito en OURS_INDEX es
// "el nuestro" (el que intentamos retirar) en todos los casos.
const DEPOSITS = [
  { nullifier: 111n, secret: 1111n },
  { nullifier: 222n, secret: 2222n }, // <- el nuestro
  { nullifier: 333n, secret: 3333n },
  { nullifier: 444n, secret: 4444n },
];
const OURS_INDEX = 1;

// Valores publicos de prueba para recipient/relayer/fee (ver binding
// xSquare<==x*x en el circuito: solo importa que viajen intactos entre
// input y publicSignals, no representan direcciones reales).
const RECIPIENT = 123n;
const RELAYER = 456n;
const FEE = 0n;

async function commitmentsOf(deposits) {
  return Promise.all(deposits.map((d) => commitmentOf(d.nullifier, d.secret)));
}

function toInput({ nullifier, secret, stateProof, assocProof, root, associationRoot, nullifierHash }) {
  return {
    nullifier: nullifier.toString(),
    secret: secret.toString(),
    pathElements: stateProof.pathElements.map(String),
    pathIndices: stateProof.pathIndices.map(String),
    assocPathElements: assocProof.pathElements.map(String),
    assocPathIndices: assocProof.pathIndices.map(String),
    root: root.toString(),
    associationRoot: associationRoot.toString(),
    nullifierHash: nullifierHash.toString(),
    recipient: RECIPIENT.toString(),
    relayer: RELAYER.toString(),
    fee: FEE.toString(),
  };
}

let vkey;
test.before(() => {
  assert.ok(fs.existsSync(WASM_PATH), `falta ${WASM_PATH} — correr circom build primero`);
  assert.ok(fs.existsSync(ZKEY_PATH), `falta ${ZKEY_PATH} — correr trusted setup primero`);
  assert.ok(fs.existsSync(VKEY_PATH), `falta ${VKEY_PATH} — correr export verificationkey primero`);
  vkey = JSON.parse(fs.readFileSync(VKEY_PATH, 'utf8'));
});

test('caso 1 (valido): deposito real y "limpio" -> genera y verifica prueba', async () => {
  // Representa el camino feliz de Privacy Pools: el depositante conoce
  // (nullifier, secret) de un commitment que esta en el arbol de TODOS
  // los depositos del pool (root) Y en el arbol de asociacion que el ASP
  // publico como "set limpio" (associationRoot). La prueba debe generarse
  // y verificar en true.
  const commitments = await commitmentsOf(DEPOSITS);
  const stateTree = await buildTree(commitments, LEVELS);

  // arbol de asociacion = subconjunto "limpio" que SI incluye el nuestro
  const assocCommitments = [commitments[0], commitments[1], commitments[2]];
  const assocTree = await buildTree(assocCommitments, LEVELS);

  const own = DEPOSITS[OURS_INDEX];
  const stateProof = getMerkleProof(stateTree, OURS_INDEX);
  const assocProof = getMerkleProof(assocTree, OURS_INDEX); // mismo indice: el subset preserva orden [0,1,2]
  const nullifierHash = await nullifierHashOf(own.nullifier);

  const input = toInput({
    nullifier: own.nullifier,
    secret: own.secret,
    stateProof,
    assocProof,
    root: stateTree.root,
    associationRoot: assocTree.root,
    nullifierHash,
  });

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH);
  const ok = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  assert.equal(ok, true);
});

test('caso 2 (invalido): commitment no pertenece al arbol de estado', async () => {
  // Representa: alguien intenta retirar un "deposito" que nunca existio
  // en el pool — su commitment no esta en ningun leaf del arbol de estado
  // vigente. Armamos un arbol de estado que NO incluye nuestro commitment
  // y le pedimos al circuito el path de OTRA hoja (index 0) de ese arbol.
  // El circuito recalcula el root desde el path usando como hoja el
  // commitment REAL (Poseidon(nullifier,secret), calculado internamente),
  // que no coincide con la hoja para la que el path fue armado, asi que
  // el root recalculado no matchea `root` (constraint
  // `root === stateProof.root` en withdraw.circom) y fullProve debe fallar.
  const commitments = await commitmentsOf(DEPOSITS);
  const own = DEPOSITS[OURS_INDEX];

  const otherCommitments = [commitments[0], commitments[2], commitments[3]]; // sin el nuestro
  const bogusStateTree = await buildTree(otherCommitments, LEVELS);
  const bogusStateProof = getMerkleProof(bogusStateTree, 0); // path de una hoja ajena

  const assocTree = await buildTree([commitments[0], commitments[1], commitments[2]], LEVELS);
  const assocProof = getMerkleProof(assocTree, OURS_INDEX);
  const nullifierHash = await nullifierHashOf(own.nullifier);

  const input = toInput({
    nullifier: own.nullifier,
    secret: own.secret,
    stateProof: bogusStateProof,
    assocProof,
    root: bogusStateTree.root,
    associationRoot: assocTree.root,
    nullifierHash,
  });

  await assert.rejects(() => snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH));
});

test('caso 3 (invalido): commitment esta en el arbol de estado pero NO en el de asociacion', async () => {
  // El caso central de Privacy Pools: un deposito REAL (esta en el arbol
  // de estado, el pool lo reconoce) pero que el ASP nunca marco "limpio"
  // -- por ejemplo porque el origen de esos fondos esta en la lista de
  // exclusion. El depositante no puede fabricar un path de asociacion
  // valido sin que el ASP lo haya incluido: armamos un arbol de asociacion
  // que excluye nuestro commitment y usamos el path de otra hoja de ESE
  // arbol. La constraint `associationRoot === assocProof.root` debe fallar.
  const commitments = await commitmentsOf(DEPOSITS);
  const own = DEPOSITS[OURS_INDEX];

  const stateTree = await buildTree(commitments, LEVELS); // el deposito SI esta aca
  const stateProof = getMerkleProof(stateTree, OURS_INDEX);

  const exclusionSet = [commitments[0], commitments[2]]; // sin el nuestro
  const bogusAssocTree = await buildTree(exclusionSet, LEVELS);
  const bogusAssocProof = getMerkleProof(bogusAssocTree, 0); // path de una hoja ajena

  const nullifierHash = await nullifierHashOf(own.nullifier);

  const input = toInput({
    nullifier: own.nullifier,
    secret: own.secret,
    stateProof,
    assocProof: bogusAssocProof,
    root: stateTree.root,
    associationRoot: bogusAssocTree.root,
    nullifierHash,
  });

  await assert.rejects(() => snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH));
});

test('caso 4 (invalido): nullifierHash publico no corresponde al nullifier privado', async () => {
  // Representa un intento de romper el anti-double-spend: si alguien
  // pudiera declarar un nullifierHash publico distinto de
  // Poseidon(nullifier), el contrato marcaria como "gastado" un hash que
  // no bloquea el nullifier real, permitiendo retirar el mismo deposito
  // mas de una vez. La constraint `nullifierHash === nullifierHasher.out`
  // en withdraw.circom debe impedirlo.
  const commitments = await commitmentsOf(DEPOSITS);
  const own = DEPOSITS[OURS_INDEX];

  const stateTree = await buildTree(commitments, LEVELS);
  const stateProof = getMerkleProof(stateTree, OURS_INDEX);
  const assocTree = await buildTree([commitments[0], commitments[1], commitments[2]], LEVELS);
  const assocProof = getMerkleProof(assocTree, OURS_INDEX);

  // nullifierHash de un nullifier distinto -- no corresponde al que
  // efectivamente se usa como input privado.
  const wrongNullifierHash = await nullifierHashOf(999999n);

  const input = toInput({
    nullifier: own.nullifier,
    secret: own.secret,
    stateProof,
    assocProof,
    root: stateTree.root,
    associationRoot: assocTree.root,
    nullifierHash: wrongNullifierHash,
  });

  await assert.rejects(() => snarkjs.groth16.fullProve(input, WASM_PATH, ZKEY_PATH));
});
