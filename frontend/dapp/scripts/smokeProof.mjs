// smokeProof.mjs — evidencia objetiva (sin browser) de que el camino de proving
// de la dApp es el mismo pipeline ya verificado en D2/D3.
//
// Reutiliza EL MISMO código de la dApp: importa commitmentOf/buildTree de
// src/lib/merkleTree.ts y buildWithdrawInput de src/lib/zk.ts (vía tsx, que
// resuelve los .ts). Arma un escenario de depósitos, construye el input del
// circuito con la MISMA función que usa el browser, y genera + verifica una
// prueba Groth16 REAL con snarkjs usando la wasm+zkey de public/zk/.
//
// El único paso que difiere del browser es la llamada a snarkjs: acá se importa
// snarkjs como módulo de Node y se le pasan rutas de archivo; en el browser es
// window.snarkjs.groth16.fullProve con URLs. La API y el resultado son
// idénticos (proveWithdraw() en zk.ts hace exactamente eso). El input y la
// lógica de árbol —lo que podría romper el matcheo de raíces— son el MISMO
// código.
//
// Uso:  npm run smoke   (o: npx tsx scripts/smokeProof.mjs)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as snarkjs from "snarkjs";

import { commitmentOf } from "../src/lib/merkleTree.ts";
import { buildWithdrawInput, parseSolidityCallData } from "../src/lib/zk.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ZK_DIR = path.join(__dirname, "..", "public", "zk");
const WASM = path.join(ZK_DIR, "withdraw.wasm");
const ZKEY = path.join(ZK_DIR, "withdraw_final.zkey");
const VKEY = path.join(ZK_DIR, "verification_key.json");

async function main() {
  for (const f of [WASM, ZKEY, VKEY]) {
    if (!fs.existsSync(f)) throw new Error(`Falta artefacto ZK: ${f}`);
  }

  // Escenario: 4 depósitos, el índice 1 es "el nuestro".
  const deposits = [
    { nullifier: 111n, secret: 1111n },
    { nullifier: 222n, secret: 2222n }, // el nuestro
    { nullifier: 333n, secret: 3333n },
    { nullifier: 444n, secret: 4444n },
  ];
  const leafIndex = 1;

  const commitments = [];
  for (const d of deposits) {
    commitments.push(await commitmentOf(d.nullifier, d.secret));
  }

  const recipient = "0x00000000000000000000000000000000000000A1";
  const relayer = "0x00000000000000000000000000000000000000B2";
  const fee = 1000000000000000n; // 0.001 ETH

  // MISMA función que usa el browser para armar el input del circuito.
  const input = await buildWithdrawInput({
    commitments,
    leafIndex,
    note: deposits[leafIndex],
    recipient,
    relayer,
    fee,
  });

  console.log("[smoke] root            =", input.root);
  console.log("[smoke] associationRoot =", input.associationRoot);
  console.log("[smoke] nullifierHash   =", input.nullifierHash);
  console.log("[smoke] generando prueba Groth16 (fullProve)…");

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);

  // Verificar contra la verification_key.json (la misma que sirve la dApp).
  const vkey = JSON.parse(fs.readFileSync(VKEY, "utf8"));
  const ok = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  if (!ok) throw new Error("La verificación de la prueba FALLÓ.");

  // Sanity-check: exportSolidityCallData se parsea a los args de withdraw(),
  // tal como hace proveWithdraw() en el browser.
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const { pA, pB, pC, pubSignals } = parseSolidityCallData(calldata);
  if (pA.length !== 2 || pB.length !== 2 || pC.length !== 2 || pubSignals.length !== 6) {
    throw new Error("El calldata parseado no tiene la forma esperada.");
  }

  // El orden de las 6 señales públicas debe ser [root, associationRoot,
  // nullifierHash, recipient, relayer, fee]. exportSolidityCallData devuelve
  // los valores en hex; comparamos por valor numérico contra el input decimal.
  if (
    BigInt(pubSignals[0]) !== BigInt(input.root) ||
    BigInt(pubSignals[1]) !== BigInt(input.associationRoot) ||
    BigInt(pubSignals[2]) !== BigInt(input.nullifierHash)
  ) {
    throw new Error("Las señales públicas no coinciden con el input.");
  }

  console.log("[smoke] pubSignals[0..5] =", pubSignals);
  console.log("PROOF OK");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
