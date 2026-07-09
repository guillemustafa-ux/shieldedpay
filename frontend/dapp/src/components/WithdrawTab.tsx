import { useState } from "react";
import { ethers } from "ethers";
import { parseNote } from "../lib/note";
import { commitmentOf } from "../lib/merkleTree";
import { buildWithdrawInput, proveWithdraw } from "../lib/zk";
import { fetchDeposits, getPool } from "../lib/pool";
import { ZK_WASM_URL, ZK_ZKEY_URL, EXPLORER } from "../config";

interface Props {
  signer: ethers.JsonRpcSigner;
  provider: ethers.BrowserProvider;
  account: string;
}

type Step = "idle" | "loading" | "proving" | "sending" | "done";

export function WithdrawTab({ signer, provider, account }: Props) {
  const [noteRaw, setNoteRaw] = useState("");
  const [recipient, setRecipient] = useState(account);
  const [step, setStep] = useState<Step>("idle");
  const [statusMsg, setStatusMsg] = useState("");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleWithdraw() {
    try {
      setError(null);
      setTxHash(null);

      // 1. Parsear la nota (secreto del usuario, nunca sale de la máquina).
      const note = parseNote(noteRaw);
      if (!ethers.isAddress(recipient)) {
        throw new Error("La dirección de destino no es válida.");
      }

      // 2. Reconstruir el árbol de estado leyendo los eventos Deposit.
      setStep("loading");
      setStatusMsg("Leyendo depósitos on-chain…");
      const deposits = await fetchDeposits(provider);
      if (deposits.length === 0) {
        throw new Error("No hay depósitos en el pool todavía.");
      }
      const commitments = deposits.map((d) => d.commitment);

      // 3. Encontrar NUESTRO commitment en el árbol.
      const myCommitment = await commitmentOf(note.nullifier, note.secret);
      const leafIndex = commitments.findIndex((c) => c === myCommitment);
      if (leafIndex === -1) {
        throw new Error(
          "No se encontró tu depósito en el pool. ¿La nota corresponde a este contrato/red?",
        );
      }

      // 4. Retiro simple para el propio usuario: sin relayer, fee 0.
      const relayer = ethers.ZeroAddress;
      const fee = 0n;

      const input = await buildWithdrawInput({
        commitments,
        leafIndex,
        note,
        recipient,
        relayer,
        fee,
      });

      // 5. Generar la prueba ZK EN EL BROWSER.
      setStep("proving");
      setStatusMsg("Generando prueba ZK en tu navegador… (puede tardar)");
      const proof = await proveWithdraw(input, ZK_WASM_URL, ZK_ZKEY_URL);

      // 6. Enviar el retiro on-chain.
      setStep("sending");
      setStatusMsg("Confirmá el retiro en la wallet…");
      const pool = getPool(signer);
      const tx = await pool.withdraw(
        proof.pA,
        proof.pB,
        proof.pC,
        proof.root,
        proof.associationRoot,
        proof.nullifierHash,
        recipient,
        relayer,
        fee,
      );
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("done");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Error en el retiro";
      setError(msg);
      setStep("idle");
    }
  }

  const busy = step === "loading" || step === "proving" || step === "sending";

  return (
    <div className="space-y-5">
      <p className="text-sm text-slate-400">
        Pegás tu nota. La dApp reconstruye el árbol del pool desde los eventos
        on-chain, arma la prueba de que tu depósito pertenece al set —{" "}
        <strong>generándola en tu propio navegador</strong> — y ejecuta el
        retiro. El secreto nunca sale de tu máquina.
      </p>

      <div className="space-y-3">
        <label className="block text-sm">
          <span className="text-slate-300">Tu nota</span>
          <textarea
            value={noteRaw}
            onChange={(e) => setNoteRaw(e.target.value)}
            disabled={busy}
            rows={2}
            placeholder="shieldedpay-note-v1-…"
            className="mt-1 w-full rounded-lg bg-slate-900/70 border border-slate-700 p-3 font-mono text-xs text-slate-200 focus:border-indigo-500 focus:outline-none disabled:opacity-50"
          />
        </label>

        <label className="block text-sm">
          <span className="text-slate-300">Dirección de destino</span>
          <input
            value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
            disabled={busy}
            className="mt-1 w-full rounded-lg bg-slate-900/70 border border-slate-700 p-3 font-mono text-xs text-slate-200 focus:border-indigo-500 focus:outline-none disabled:opacity-50"
          />
        </label>
      </div>

      <button
        onClick={handleWithdraw}
        disabled={busy || !noteRaw.trim()}
        className="w-full py-3 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold transition-colors cursor-pointer flex items-center justify-center gap-2"
      >
        {busy && (
          <span className="size-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
        )}
        {busy ? statusMsg || "Procesando…" : "Retirar"}
      </button>

      {step === "done" && txHash && (
        <div className="rounded-lg border border-emerald-500/40 bg-emerald-500/10 p-4 text-sm text-emerald-200">
          Retiro confirmado. Los fondos fueron enviados a la dirección de
          destino.
          <div className="mt-2">
            <a
              href={`${EXPLORER}/tx/${txHash}`}
              target="_blank"
              rel="noreferrer"
              className="underline text-emerald-300"
            >
              Ver transacción
            </a>
          </div>
        </div>
      )}

      {error && (
        <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300 break-words">
          {error}
        </div>
      )}
    </div>
  );
}
