import { useState } from "react";
import { ethers } from "ethers";
import { generateNote, serializeNote, type Note } from "../lib/note";
import { commitmentOf } from "../lib/merkleTree";
import { getPool, getDenomination } from "../lib/pool";
import { EXPLORER } from "../config";

interface Props {
  signer: ethers.JsonRpcSigner;
  provider: ethers.BrowserProvider;
}

type Step = "idle" | "generating" | "ready" | "sending" | "done";

export function DepositTab({ signer, provider }: Props) {
  const [step, setStep] = useState<Step>("idle");
  const [note, setNote] = useState<Note | null>(null);
  const [commitment, setCommitment] = useState<bigint | null>(null);
  const [denomEth, setDenomEth] = useState<string>("");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function handleGenerate() {
    try {
      setError(null);
      setStep("generating");
      const n = generateNote();
      const c = await commitmentOf(n.nullifier, n.secret);
      const denom = await getDenomination(provider);
      setNote(n);
      setCommitment(c);
      setDenomEth(ethers.formatEther(denom));
      setStep("ready");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Error generando la nota");
      setStep("idle");
    }
  }

  async function handleDeposit() {
    if (!note || commitment === null) return;
    try {
      setError(null);
      setStep("sending");
      const denom = await getDenomination(provider);
      const pool = getPool(signer);
      const tx = await pool.deposit(commitment, { value: denom });
      const receipt = await tx.wait();
      setTxHash(receipt.hash);
      setStep("done");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Error en el depósito");
      setStep("ready");
    }
  }

  async function copyNote() {
    if (!note) return;
    await navigator.clipboard.writeText(serializeNote(note));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  function reset() {
    setStep("idle");
    setNote(null);
    setCommitment(null);
    setTxHash(null);
    setError(null);
  }

  return (
    <div className="space-y-5">
      <p className="text-sm text-slate-400">
        Depositás una cantidad fija de ETH publicando sólo un <em>commitment</em>{" "}
        (Poseidon del secreto). Nadie puede vincular tu depósito con tu retiro
        futuro. Guardá la nota que te da la dApp: es lo único que te permite
        retirar.
      </p>

      {step === "idle" && (
        <button
          onClick={handleGenerate}
          className="w-full py-3 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-semibold transition-colors cursor-pointer"
        >
          Generar nota nueva
        </button>
      )}

      {step === "generating" && (
        <div className="text-slate-400 text-sm">Generando commitment…</div>
      )}

      {note && commitment !== null && step !== "done" && (
        <div className="space-y-4">
          <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4">
            <div className="text-amber-300 font-semibold text-sm mb-2">
              Guardá tu nota AHORA
            </div>
            <p className="text-xs text-amber-200/80 mb-3">
              Sin esta nota no vas a poder retirar los fondos. Nadie la puede
              recuperar por vos. Copiala y guardala en un lugar seguro antes de
              depositar.
            </p>
            <div className="font-mono text-xs break-all bg-slate-900/70 rounded p-3 text-slate-200 select-all">
              {serializeNote(note)}
            </div>
            <button
              onClick={copyNote}
              className="mt-2 text-xs px-3 py-1.5 rounded border border-amber-500/40 text-amber-200 hover:bg-amber-500/10 cursor-pointer"
            >
              {copied ? "Copiada ✓" : "Copiar nota"}
            </button>
          </div>

          <div className="text-xs text-slate-500 space-y-1">
            <div>
              <span className="text-slate-400">Commitment:</span>{" "}
              <span className="font-mono break-all">{commitment.toString()}</span>
            </div>
            {denomEth && (
              <div>
                <span className="text-slate-400">Monto a depositar:</span>{" "}
                {denomEth} ETH
              </div>
            )}
          </div>

          <button
            onClick={handleDeposit}
            disabled={step === "sending"}
            className="w-full py-3 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold transition-colors cursor-pointer"
          >
            {step === "sending" ? "Confirmá en la wallet…" : `Depositar ${denomEth} ETH`}
          </button>
        </div>
      )}

      {step === "done" && txHash && (
        <div className="space-y-3">
          <div className="rounded-lg border border-emerald-500/40 bg-emerald-500/10 p-4 text-sm text-emerald-200">
            Depósito confirmado. Recordá que ya guardaste tu nota: la vas a
            necesitar en la pestaña Retirar.
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
          <button
            onClick={reset}
            className="text-sm text-slate-400 hover:text-white cursor-pointer"
          >
            Hacer otro depósito
          </button>
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
