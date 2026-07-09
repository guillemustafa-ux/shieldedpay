// Port a TypeScript del harness circuits/test/merkleTree.js (verificado en
// D2/D3). MISMA lógica, MISMO ZERO_VALUE, MISMO hasher (Poseidon(2) vía
// circomlibjs). Si algo de esto cambia, las raíces dejan de matchear las que
// calcula el circuito y el contrato, y las pruebas fallan. circomlibjs corre
// tanto en Node como en el browser, así que este módulo es reutilizable por la
// dApp (browser) y por el smoke test (Node) sin cambios.

import { buildPoseidon } from "circomlibjs";

export const LEVELS = 20;

// keccak256("shieldedpay") mod FIELD_SIZE (BN254). "Nothing-up-my-sleeve":
// hoja vacía derivada de forma pública y reproducible (ver comentario extenso
// en circuits/test/merkleTree.js).
export const ZERO_VALUE =
  9880778443085210058860878218881645598704289061394908001763061260920381531404n;

export interface MerkleTree {
  root: bigint;
  layers: bigint[][];
  levels: number;
  zeros: bigint[];
}

export interface MerkleProof {
  pathElements: bigint[];
  pathIndices: number[];
  root: bigint;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let poseidonSingleton: any = null;
let zerosSingleton: bigint[] | null = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPoseidon(): Promise<any> {
  if (!poseidonSingleton) {
    poseidonSingleton = await buildPoseidon();
  }
  return poseidonSingleton;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function poseidonHash2(poseidon: any, a: bigint, b: bigint): bigint {
  return poseidon.F.toObject(poseidon([a, b])) as bigint;
}

// zeros[i] = Poseidon-hash de un subárbol vacío de altura i.
export async function computeZeros(levels = LEVELS): Promise<bigint[]> {
  if (zerosSingleton && zerosSingleton.length === levels + 1) return zerosSingleton;
  const poseidon = await getPoseidon();
  const zeros: bigint[] = [ZERO_VALUE];
  for (let i = 1; i <= levels; i++) {
    zeros.push(poseidonHash2(poseidon, zeros[i - 1], zeros[i - 1]));
  }
  zerosSingleton = zeros;
  return zeros;
}

// Construye un árbol incremental disperso de altura `levels` a partir de
// `leaves` (commitments), en orden de inserción (índice 0 = primera hoja).
export async function buildTree(leaves: bigint[], levels = LEVELS): Promise<MerkleTree> {
  const poseidon = await getPoseidon();
  const zeros = await computeZeros(levels);
  const layers: bigint[][] = [leaves.slice()];
  let current = leaves.slice();
  for (let level = 0; level < levels; level++) {
    const next: bigint[] = [];
    for (let i = 0; i < current.length; i += 2) {
      const left = current[i];
      const right = i + 1 < current.length ? current[i + 1] : zeros[level];
      next.push(poseidonHash2(poseidon, left, right));
    }
    layers.push(next);
    current = next;
  }
  const root = current.length > 0 ? current[0] : zeros[levels];
  return { root, layers, levels, zeros };
}

// Dado un árbol y el índice de una hoja, devuelve el Merkle path que espera el
// circuito withdraw. pathIndices[i] = idx % 2 (0 = hijo izquierdo).
export function getMerkleProof(tree: MerkleTree, index: number): MerkleProof {
  const { layers, levels, zeros, root } = tree;
  let idx = index;
  const pathElements: bigint[] = [];
  const pathIndices: number[] = [];
  for (let level = 0; level < levels; level++) {
    const layer = layers[level];
    const siblingIndex = idx ^ 1;
    const sibling = siblingIndex < layer.length ? layer[siblingIndex] : zeros[level];
    pathElements.push(sibling);
    pathIndices.push(idx % 2);
    idx = Math.floor(idx / 2);
  }
  return { pathElements, pathIndices, root };
}

// Poseidon(nullifier, secret) — fórmula del commitment de withdraw.circom.
export async function commitmentOf(nullifier: bigint, secret: bigint): Promise<bigint> {
  const poseidon = await getPoseidon();
  return poseidonHash2(poseidon, nullifier, secret);
}

// Poseidon(nullifier) — fórmula del nullifierHash.
export async function nullifierHashOf(nullifier: bigint): Promise<bigint> {
  const poseidon = await getPoseidon();
  return poseidon.F.toObject(poseidon([nullifier])) as bigint;
}
