import { useState, useEffect } from "react";
import { ethers } from "ethers";
import { parseNote } from "../lib/note";
import { commitmentOf } from "../lib/merkleTree";
import { buildWithdrawInput, proveWithdraw } from "../lib/zk";
import { fetchDeposits, getPool, getRegistry, fetchAsps, type AspInfo } from "../lib/pool";
import { ZK_WASM_URL, ZK_ZKEY_URL, EXPLORER } from "../config";

interface Props {
  signer: ethers.JsonRpcSigner;
  provider: ethers.BrowserProvider;
  account: string;
}

type Step = "idle" | "loading" | "proving" | "sending" | "done";

function shortAddr(a: string): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

function shortRoot(r: bigint): string {
  if (r === 0n) return "sin root publicada";
  const hex = r.toString(16);
  return `0x${hex.slice(0, 6)}…${hex.slice(-4)}`;
}

export function WithdrawTab({ signer, provider, account }: Props) {
  const [noteRaw, setNoteRaw] = useState("");
  const [recipient, setRecipient] = useState(account);
  const [step, setStep] = useState<Step>("idle");
  const [statusMsg, setStatusMsg] = useState("");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Lista de ASPs del registry y el elegido por el usuario.
  const [asps, setAsps] = useState<AspInfo[] | null>(null);
  const [selectedAspId, setSelectedAspId] = useState<number | null>(null);

  // Cargar los ASPs del registry al montar: el usuario elige contra cuál validar.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const list = await fetchAsps(provider);
        if (cancelled) return;
        setAsps(list);
        // Pre-seleccionar el primer ASP activo con una root publicada.
        const firstUsable = list.find((a) => a.active && a.latestRoot !== 0n);
        if (firstUsable) setSelectedAspId(firstUsable.id);
      } catch {
        if (!cancelled) setAsps([]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [provider]);

  async function handleWithdraw() {
    try {
      setError(null);
      setTxHash(null);

      if (selectedAspId === null) {
        throw new Error("Elegí un ASP activo contra el que validar tu retiro.");
      }

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

      // 4b. El pool exige que el ASP elegido haya publicado ESTA associationRoot.
      // Lo validamos ANTES de gastar tiempo probando, para dar feedback claro.
      const registry = getRegistry(provider);
      const known = await registry.isKnownRoot(selectedAspId, BigInt(input.associationRoot));
      if (!known) {
        throw new Error(
          `El ASP #${selectedAspId} no publicó la root actual del pool. Elegí un ASP que la haya publicado, o pedí que se publique la root vigente.`,
        );
      }

      // 5. Generar la prueba ZK EN EL BROWSER.
      setStep("proving");
      setStatusMsg("Generando prueba ZK en tu navegador… (puede tardar)");
      const proof = await proveWithdraw(input, ZK_WASM_URL, ZK_ZKEY_URL);

      // 6. Enviar el retiro on-chain, seleccionando el ASP elegido (aspId).
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
        selectedAspId,
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
        Pegás tu nota y <strong>elegís el ASP</strong> contra el que querés
        validar tu retiro. La dApp reconstruye el árbol del pool desde los
        eventos on-chain, arma la prueba de que tu depósito pertenece al set —{" "}
        <strong>generándola en tu propio navegador</strong> — y ejecuta el
        retiro. El secreto nunca sale de tu máquina.
      </p>

      {/* Selector de ASP: la lista real del registry on-chain. */}
      <div className="space-y-2">
        <span className="text-sm text-slate-300">Association Set Provider</span>
        {asps === null ? (
          <div className="text-xs text-slate-500">Leyendo ASPs del registry…</div>
        ) : asps.length === 0 ? (
          <div className="text-xs text-slate-500">
            No hay ASPs registrados en el registry.
          </div>
        ) : (
          <div className="space-y-2">
            {asps.map((asp) => {
              const usable = asp.active && asp.latestRoot !== 0n;
              const selected = asp.id === selectedAspId;
              return (
                <button
                  key={asp.id}
                  onClick={() => usable && setSelectedAspId(asp.id)}
                  disabled={!usable || busy}
                  className={`w-full text-left rounded-lg border p-3 transition-colors ${
                    selected
                      ? "border-indigo-500 bg-indigo-500/10"
                      : usable
                        ? "border-slate-700 bg-slate-900/50 hover:border-slate-500 cursor-pointer"
                        : "border-red-500/30 bg-red-500/5 opacity-70 cursor-not-allowed"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-slate-200">
                      ASP #{asp.id}{" "}
                      <span className="font-mono text-xs text-slate-500">
                        {shortAddr(asp.owner)}
                      </span>
                    </span>
                    {asp.slashed ? (
                      <span className="text-[10px] uppercase tracking-wider text-red-300 border border-red-500/40 rounded px-1.5 py-0.5">
                        Slashed
                      </span>
                    ) : (
                      <span className="text-[10px] uppercase tracking-wider text-emerald-300 border border-emerald-500/40 rounded px-1.5 py-0.5">
                        Activo
                      </span>
                    )}
                  </div>
                  <div className="mt-1 flex items-center gap-3 text-xs text-slate-500">
                    <span>stake {ethers.formatEther(asp.stake)} ETH</span>
                    <span className="font-mono">root {shortRoot(asp.latestRoot)}</span>
                  </div>
                </button>
              );
            })}
            <p className="text-[11px] text-slate-600">
              Un ASP <span className="text-red-300">slashed</span> fue penalizado
              por un fraud proof on-chain y no se puede elegir. El pool valida tu
              retiro contra el ASP que elijas (<code className="font-mono">aspId</code>).
            </p>
          </div>
        )}
      </div>

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
        disabled={busy || !noteRaw.trim() || selectedAspId === null}
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
