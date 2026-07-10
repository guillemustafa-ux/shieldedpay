import { useState } from "react";
import { useWallet } from "./hooks/useWallet";
import { ConnectWallet } from "./components/ConnectWallet";
import { DepositTab } from "./components/DepositTab";
import { WithdrawTab } from "./components/WithdrawTab";
import { StealthTab } from "./components/StealthTab";
import { SEPOLIA_CHAIN_ID, addressesConfigured } from "./config";

type Tab = "deposit" | "withdraw" | "stealth";

const TAB_LABELS: Record<Tab, string> = {
  deposit: "Depositar",
  withdraw: "Retirar",
  stealth: "Stealth",
};

export default function App() {
  const wallet = useWallet();
  const [tab, setTab] = useState<Tab>("deposit");

  const wrongNetwork =
    wallet.account !== null && wallet.chainId !== SEPOLIA_CHAIN_ID;
  const configured = addressesConfigured();

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-slate-800">
        <div className="max-w-2xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-lg font-bold tracking-tight text-white">
              Shielded<span className="text-indigo-400">Pay</span>
            </span>
            <span className="text-[10px] uppercase tracking-wider text-slate-500 border border-slate-700 rounded px-1.5 py-0.5">
              Sepolia
            </span>
          </div>
          <ConnectWallet
            account={wallet.account}
            isConnecting={wallet.isConnecting}
            onConnect={wallet.connect}
            onDisconnect={wallet.disconnect}
          />
        </div>
      </header>

      <main className="flex-1">
        <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
          {/* Disclaimer */}
          <div className="rounded-lg border border-slate-700 bg-slate-900/50 p-3 text-xs text-slate-400">
            Proyecto educativo · testnet · <strong>no auditado</strong> · no usar
            con fondos reales. La prueba de retiro se genera enteramente en tu
            navegador con snarkjs (wasm); ningún dato secreto sale de tu máquina.
          </div>

          {/* Banner de configuración */}
          {!configured && (
            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-200">
              Configurá <code className="font-mono">VITE_POOL_ADDRESS</code> y{" "}
              <code className="font-mono">VITE_ASP_ADDRESS</code> con las
              direcciones desplegadas en Sepolia. Sin esto, las operaciones
              on-chain no van a funcionar.
            </div>
          )}

          {/* Nota sobre la simplificación de demo del ASP */}
          <div className="rounded-lg border border-slate-700 bg-slate-900/50 p-3 text-xs text-slate-500">
            En esta demo el ASP incluye todos los depósitos en el set limpio. El
            mecanismo de exclusión (rechazar depósitos marcados) está ejercitado
            en los tests de los contratos, no en el happy-path de la dApp.
          </div>

          {/* Aviso de red equivocada */}
          {wrongNetwork && (
            <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300 flex items-center justify-between gap-3">
              <span>Estás en la red equivocada. ShieldedPay corre en Sepolia.</span>
              <button
                onClick={wallet.switchToSepolia}
                className="shrink-0 px-3 py-1.5 rounded border border-red-400/50 text-red-200 hover:bg-red-500/10 cursor-pointer text-xs"
              >
                Cambiar a Sepolia
              </button>
            </div>
          )}

          {wallet.error && (
            <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300">
              {wallet.error}
            </div>
          )}

          {/* Contenido principal */}
          {!wallet.account ? (
            <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-8 text-center">
              <p className="text-slate-400 text-sm mb-4">
                Conectá tu wallet en Sepolia para depositar o retirar.
              </p>
              <ConnectWallet
                account={wallet.account}
                isConnecting={wallet.isConnecting}
                onConnect={wallet.connect}
                onDisconnect={wallet.disconnect}
              />
            </div>
          ) : (
            <div className="rounded-xl border border-slate-800 bg-slate-900/40 overflow-hidden">
              <div className="flex border-b border-slate-800">
                {(["deposit", "withdraw", "stealth"] as Tab[]).map((t) => (
                  <button
                    key={t}
                    onClick={() => setTab(t)}
                    className={`flex-1 py-3 text-sm font-medium transition-colors cursor-pointer ${
                      tab === t
                        ? "text-white bg-slate-800/60"
                        : "text-slate-500 hover:text-slate-300"
                    }`}
                  >
                    {TAB_LABELS[t]}
                  </button>
                ))}
              </div>
              <div className="p-5">
                {tab === "stealth" ? (
                  // La cripto de stealth corre 100% local; no requiere Sepolia.
                  <StealthTab signer={wallet.signer!} />
                ) : wrongNetwork ? (
                  <p className="text-sm text-slate-500 text-center py-6">
                    Cambiá a Sepolia para operar.
                  </p>
                ) : tab === "deposit" ? (
                  <DepositTab signer={wallet.signer!} provider={wallet.provider!} />
                ) : (
                  <WithdrawTab
                    signer={wallet.signer!}
                    provider={wallet.provider!}
                    account={wallet.account}
                  />
                )}
              </div>
            </div>
          )}
        </div>
      </main>

      <footer className="border-t border-slate-800">
        <div className="max-w-2xl mx-auto px-4 py-4 text-center text-xs text-slate-600">
          ShieldedPay — Privacy Pool (depósito/retiro anónimo con prueba
          zk-SNARK Groth16 en el cliente). Proyecto de portfolio.
        </div>
      </footer>
    </div>
  );
}
