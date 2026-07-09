'use strict';

// genPoseidon.js — genera los artefactos que el árbol on-chain necesita para
// producir EXACTAMENTE los mismos hashes que el harness JS (merkleTree.js) y,
// por transitividad, que el circuito withdraw.circom.
//
// Produce dos cosas:
//
//   1) test/fixtures/poseidonBytecode.txt — el bytecode de deploy del contrato
//      Poseidon(2) generado por circomlibjs (`poseidonContract.createCode(2)`).
//      Es EL MISMO Poseidon que usa circomlibjs.buildPoseidon() en el harness y
//      el que instancia el circuito (`Poseidon(2)`), así que hashea bit-a-bit
//      igual. Lo deployamos on-chain desde este bytecode (patrón Tornado Cash /
//      Privacy Pools) en tests y en el script de deploy. Su ABI expone:
//        function poseidon(uint256[2] input) external pure returns (uint256)
//
//   2) Imprime por stdout los 21 valores zeros[0..20] que computa
//      computeZeros(20) del harness, para pegarlos hardcodeados en la función
//      `zeros()` de src/MerkleTreeWithHistory.sol (mismo patrón que Tornado:
//      constantes precomputadas, no se calculan en runtime).
//
// Uso:  node circuits/scripts/genPoseidon.js

const fs = require('node:fs');
const path = require('node:path');
const { poseidonContract } = require('circomlibjs');
const { computeZeros, LEVELS } = require('../test/merkleTree.js');

async function main() {
  // --- 1) bytecode del hasher Poseidon(2) ---
  const bytecode = poseidonContract.createCode(2); // "0x..."
  const fixturesDir = path.join(__dirname, '..', '..', 'test', 'fixtures');
  fs.mkdirSync(fixturesDir, { recursive: true });
  const outPath = path.join(fixturesDir, 'poseidonBytecode.txt');
  fs.writeFileSync(outPath, bytecode.trim(), 'utf8');
  console.error(`[genPoseidon] bytecode Poseidon(2) escrito en ${outPath} (${bytecode.length} chars)`);

  // --- 2) zeros[0..20] para hardcodear en Solidity ---
  const zeros = await computeZeros(LEVELS); // 21 valores
  console.log('// zeros[0..20] — pegar en MerkleTreeWithHistory.zeros()');
  zeros.forEach((z, i) => {
    console.log(`        if (i == ${i}) return ${z.toString()};`);
  });
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
