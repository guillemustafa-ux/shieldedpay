'use strict';

// Incremental (sparse) Merkle tree helper for ShieldedPay's withdraw circuit.
//
// The circuit (circuits/withdraw.circom via lib/merkleProof.circom) verifies
// membership against trees of fixed height `LEVELS = 20` (2^20 possible
// leaves), hashed level-by-level with Poseidon(2) — same hasher as
// circomlib's `Poseidon` template used inside the circuit. `circomlibjs`'s
// `buildPoseidon()` is the official JS counterpart of that same hasher, so
// hashes computed here match what the circuit computes bit-for-bit.
//
// We do NOT materialize a real 2^20-leaf array (impossible in memory/time).
// Instead we build a "sparse" tree: only the branches that actually contain
// real leaves are computed; any sibling on the empty side of the tree reuses
// a precomputed "empty subtree of height i" hash (`zeros[i]`). This is the
// standard incremental Merkle tree pattern (Tornado Cash / Semaphore /
// most Privacy Pools implementations use the same trick) and is exactly
// what D3's on-chain PrivacyPool Merkle library will also need to mirror,
// so this module is written to be reused as-is (or ported to Solidity 1:1)
// in D3/D4.
//
// ZERO_VALUE (empty leaf) design decision:
//   We use a "nothing-up-my-sleeve" value instead of a bare `0n`: even though
//   claiming a fake leaf of value `0n` would require finding
//   (nullifier, secret) such that Poseidon(nullifier, secret) = 0 — assumed
//   infeasible under Poseidon's preimage resistance, same as any other
//   target value — using a hash-derived constant follows the same
//   convention as Tornado Cash's ZERO_VALUE (keccak256("tornado") mod p)
//   so nobody reviewing this later has to *trust* that 0 has no exploitable
//   structure; the derivation is public and reproducible:
//
//     keccak256("shieldedpay") mod FIELD_SIZE
//       = 0x15d85289bf289cc3360ea6f8f956c1cd07b36b92edb7ec1446c81a64a7a0650c mod p
//       = 9880778443085210058860878218881645598704289061394908001763061260920381531404
//
//   where FIELD_SIZE is the BN254 scalar field snarkjs/circom use by default:
//     21888242871839275222246405745257275088548364400416034343698204186575808495617
const { buildPoseidon } = require('circomlibjs');

const LEVELS = 20;

const ZERO_VALUE = 9880778443085210058860878218881645598704289061394908001763061260920381531404n;

let poseidonSingleton = null;
let zerosSingleton = null;

async function getPoseidon() {
  if (!poseidonSingleton) {
    poseidonSingleton = await buildPoseidon();
  }
  return poseidonSingleton;
}

function poseidonHash2(poseidon, a, b) {
  return poseidon.F.toObject(poseidon([a, b]));
}

// zeros[i] = Poseidon-hash of an empty subtree of height i.
// zeros[0]     = ZERO_VALUE (the empty leaf itself)
// zeros[i]     = Poseidon(zeros[i-1], zeros[i-1])  for i = 1..levels
async function computeZeros(levels = LEVELS) {
  if (zerosSingleton && zerosSingleton.length === levels + 1) return zerosSingleton;
  const poseidon = await getPoseidon();
  const zeros = [ZERO_VALUE];
  for (let i = 1; i <= levels; i++) {
    zeros.push(poseidonHash2(poseidon, zeros[i - 1], zeros[i - 1]));
  }
  zerosSingleton = zeros;
  return zeros;
}

// Builds a sparse incremental Merkle tree of height `levels` from `leaves`
// (array of bigint commitments), in insertion order (index 0 = first leaf).
//
// Returns { root, layers, levels, zeros } where layers[0] = leaves (as given)
// and layers[levels] = [root]. Only the "real" (non-empty) part of each
// layer is stored; getMerkleProof() below falls back to `zeros[level]` for
// any sibling past the end of a layer.
async function buildTree(leaves, levels = LEVELS) {
  const poseidon = await getPoseidon();
  const zeros = await computeZeros(levels);
  const layers = [leaves.slice()];
  let current = leaves.slice();
  for (let level = 0; level < levels; level++) {
    const next = [];
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

// Given a tree from buildTree() and the index of a leaf in it, returns the
// Merkle path { pathElements, pathIndices, root } the withdraw circuit
// expects: pathIndices[i] = 0 means the node we're carrying at level i is
// the LEFT child (sibling pathElements[i] is on the right); 1 means the
// opposite. This matches lib/merkleProof.circom's selector:
//   left  = pathIndices==0 ? carried : sibling
//   right = pathIndices==0 ? sibling : carried
function getMerkleProof(tree, index) {
  const { layers, levels, zeros, root } = tree;
  let idx = index;
  const pathElements = [];
  const pathIndices = [];
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

// Convenience: Poseidon(nullifier, secret) — the commitment formula from
// withdraw.circom — and Poseidon(nullifier) — the nullifierHash formula.
async function commitmentOf(nullifier, secret) {
  const poseidon = await getPoseidon();
  return poseidonHash2(poseidon, nullifier, secret);
}

async function nullifierHashOf(nullifier) {
  const poseidon = await getPoseidon();
  return poseidon.F.toObject(poseidon([nullifier]));
}

module.exports = {
  LEVELS,
  ZERO_VALUE,
  getPoseidon,
  computeZeros,
  buildTree,
  getMerkleProof,
  commitmentOf,
  nullifierHashOf,
};
