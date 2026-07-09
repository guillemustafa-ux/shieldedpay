// Generación de la prueba Groth16 de retiro EN EL BROWSER.
//
// El diferencial de ShieldedPay: la prueba se calcula del lado del cliente con
// snarkjs (wasm), reutilizando EXACTAMENTE la misma withdraw.wasm y
// withdraw_final.zkey que el pipeline verificado (D2/D3). Ningún dato secreto
// (nullifier, secret) sale de la máquina del usuario.
//
// snarkjs se toma de window.snarkjs (script global cargado en index.html), no
// como import ESM: asume globals de Node y no se empaqueta limpio con Vite.
// circomlibjs (Poseidon, vía merkleTree.ts) sí se empaqueta normal.

import { buildTree, getMerkleProof, nullifierHashOf, LEVELS } from "./merkleTree";
import type { Note } from "./note";

// Input del circuito withdraw.circom. Todos los campos como string decimal
// (lo que snarkjs espera). El ORDEN de las 6 señales públicas que el circuito
// expone y que el contrato valida es, fijo:
//   [root, associationRoot, nullifierHash, recipient, relayer, fee]
export interface WithdrawCircuitInput {
  nullifier: string;
  secret: string;
  pathElements: string[];
  pathIndices: string[];
  assocPathElements: string[];
  assocPathIndices: string[];
  root: string;
  associationRoot: string;
  nullifierHash: string;
  recipient: string;
  relayer: string;
  fee: string;
}

export interface WithdrawParams {
  // Commitments del árbol de estado, EN ORDEN DE INSERCIÓN (leídos de los
  // eventos Deposit on-chain).
  commitments: bigint[];
  // Índice de nuestra hoja dentro de `commitments`.
  leafIndex: number;
  note: Note;
  recipient: string; // dirección 0x…
  relayer: string; // dirección 0x… (address(0) si retira el propio usuario)
  fee: bigint;
}

// Convierte una dirección 0x… a field element (uint256(uint160(addr))), tal
// como el circuito la recibió al generar la prueba y como el contrato la
// reconstruye en `pub`.
function addressToField(addr: string): bigint {
  return BigInt(addr);
}

// Construye el input del circuito. Lógica PURA (sin browser): reutilizada tal
// cual por el smoke test en Node, garantizando que el camino de proving de la
// dApp es el mismo que ya se verificó.
//
// SIMPLIFICACIÓN DE DEMO (documentada): asumimos que el association set incluye
// TODOS los depósitos (el ASP marca todo como limpio en la demo). Entonces el
// árbol de asociación == árbol de estado y associationRoot == root. Se
// reconstruye UN solo árbol de los eventos Deposit y se usa para ambas pruebas
// de membresía. El mecanismo de exclusión (rechazar depósitos marcados) está
// ejercitado en los tests de los contratos, no en el happy-path de la dApp.
export async function buildWithdrawInput(
  params: WithdrawParams,
): Promise<WithdrawCircuitInput> {
  const { commitments, leafIndex, note, recipient, relayer, fee } = params;

  const stateTree = await buildTree(commitments, LEVELS);
  const stateProof = getMerkleProof(stateTree, leafIndex);
  // Demo: árbol de asociación == árbol de estado.
  const assocProof = stateProof;

  const nullifierHash = await nullifierHashOf(note.nullifier);

  return {
    nullifier: note.nullifier.toString(),
    secret: note.secret.toString(),
    pathElements: stateProof.pathElements.map(String),
    pathIndices: stateProof.pathIndices.map(String),
    assocPathElements: assocProof.pathElements.map(String),
    assocPathIndices: assocProof.pathIndices.map(String),
    root: stateTree.root.toString(),
    associationRoot: stateTree.root.toString(),
    nullifierHash: nullifierHash.toString(),
    recipient: addressToField(recipient).toString(),
    relayer: addressToField(relayer).toString(),
    fee: fee.toString(),
  };
}

// Prueba formateada para el contrato: args de withdraw(pA, pB, pC, …).
export interface SolidityProof {
  pA: [string, string];
  pB: [[string, string], [string, string]];
  pC: [string, string];
  pubSignals: string[]; // [root, associationRoot, nullifierHash, recipient, relayer, fee]
  root: string;
  associationRoot: string;
  nullifierHash: string;
}

// Parsea la salida de snarkjs.groth16.exportSolidityCallData a arrays limpios.
// exportSolidityCallData maneja el orden de coordenadas de G2 que el verifier
// espera (snarkjs lo invierte internamente). Misma conversión que
// circuits/scripts/genWithdrawFixture.js.
export function parseSolidityCallData(calldata: string): {
  pA: [string, string];
  pB: [[string, string], [string, string]];
  pC: [string, string];
  pubSignals: string[];
} {
  const parsed = JSON.parse("[" + calldata + "]");
  return {
    pA: parsed[0],
    pB: parsed[1],
    pC: parsed[2],
    pubSignals: parsed[3],
  };
}

// Genera la prueba en el browser con snarkjs (window.snarkjs). Requiere las
// URLs de la wasm y la zkey servidas desde public/zk/.
export async function proveWithdraw(
  input: WithdrawCircuitInput,
  wasmUrl: string,
  zkeyUrl: string,
): Promise<SolidityProof> {
  const snarkjs = window.snarkjs;
  if (!snarkjs?.groth16) {
    throw new Error(
      "snarkjs no está cargado (window.snarkjs). Revisá que /snarkjs.min.js se sirva.",
    );
  }

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, wasmUrl, zkeyUrl);
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const { pA, pB, pC, pubSignals } = parseSolidityCallData(calldata);

  return {
    pA,
    pB,
    pC,
    pubSignals,
    root: input.root,
    associationRoot: input.associationRoot,
    nullifierHash: input.nullifierHash,
  };
}
