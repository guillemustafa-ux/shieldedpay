import { useState } from "react";
import { ethers } from "ethers";
import {
  generateStealthMetaAddress,
  generateStealthAddress,
  computeStealthKey,
  checkStealthAddress,
  addressFromPrivateKey,
  type StealthMetaAddress,
  type StealthPayment,
  type DerivedKey,
  type ScanResult,
} from "../lib/stealth";
import {
  EXPLORER,
  REGISTRY_ADDRESS,
  REGISTRY_ABI,
  ANNOUNCER_ADDRESS,
  ANNOUNCER_ABI,
  STEALTH_SCHEME_ID,
  registryConfigured,
  announcerConfigured,
} from "../config";

interface Props {
  signer: ethers.JsonRpcSigner;
}

// metadata del anuncio ERC-5564: su primer byte es el view tag.
function viewTagToMetadata(viewTag: number): string {
  return "0x" + viewTag.toString(16).padStart(2, "0");
}

export function StealthTab({ signer }: Props) {
  // Receptor (Bob)
  const [bob, setBob] = useState<StealthMetaAddress | null>(null);
  const [showBobKeys, setShowBobKeys] = useState(false);
  const [registerTx, setRegisterTx] = useState<string | null>(null);
  const [registering, setRegistering] = useState(false);

  // Pagador (Alice)
  const [metaInput, setMetaInput] = useState("");
  const [payment, setPayment] = useState<StealthPayment | null>(null);
  const [announceTx, setAnnounceTx] = useState<string | null>(null);
  const [announcing, setAnnouncing] = useState(false);

  // Receptor de nuevo (Bob deriva)
  const [derived, setDerived] = useState<DerivedKey | null>(null);
  const [scan, setScan] = useState<ScanResult | null>(null);

  const [error, setError] = useState<string | null>(null);

  function fail(e: unknown, fallback: string) {
    setError(e instanceof Error ? e.message : fallback);
  }

  // --- Receptor (Bob) ---
  function handleGenerateMeta() {
    try {
      setError(null);
      setBob(generateStealthMetaAddress());
      // reset de los pasos posteriores que dependen de estas claves
      setPayment(null);
      setDerived(null);
      setScan(null);
      setRegisterTx(null);
    } catch (e) {
      fail(e, "Error generando el meta-address");
    }
  }

  async function handleRegister() {
    if (!bob) return;
    try {
      setError(null);
      setRegistering(true);
      const registry = new ethers.Contract(REGISTRY_ADDRESS, REGISTRY_ABI, signer);
      const tx = await registry.registerKeys(STEALTH_SCHEME_ID, bob.metaAddress);
      const receipt = await tx.wait();
      setRegisterTx(receipt.hash);
    } catch (e) {
      fail(e, "Error registrando en ERC6538");
    } finally {
      setRegistering(false);
    }
  }

  // --- Pagador (Alice) ---
  function handleGeneratePayment() {
    try {
      setError(null);
      const meta = metaInput.trim();
      if (!meta) {
        setError("Pegá el meta-address del receptor.");
        return;
      }
      setPayment(generateStealthAddress(meta));
      setDerived(null);
      setScan(null);
      setAnnounceTx(null);
    } catch (e) {
      fail(e, "Meta-address inválido");
    }
  }

  async function handleAnnounce() {
    if (!payment) return;
    try {
      setError(null);
      setAnnouncing(true);
      const announcer = new ethers.Contract(ANNOUNCER_ADDRESS, ANNOUNCER_ABI, signer);
      const tx = await announcer.announce(
        STEALTH_SCHEME_ID,
        payment.stealthAddress,
        payment.ephemeralPubKey,
        viewTagToMetadata(payment.viewTag),
      );
      const receipt = await tx.wait();
      setAnnounceTx(receipt.hash);
    } catch (e) {
      fail(e, "Error anunciando en ERC5564");
    } finally {
      setAnnouncing(false);
    }
  }

  // --- Receptor de nuevo (Bob deriva la privkey) ---
  function handleDerive() {
    if (!bob || !payment) return;
    try {
      setError(null);
      const d = computeStealthKey({
        ephemeralPubKey: payment.ephemeralPubKey,
        spendingPrivateKey: bob.spendingPrivateKey,
        viewingPrivateKey: bob.viewingPrivateKey,
      });
      const s = checkStealthAddress({
        ephemeralPubKey: payment.ephemeralPubKey,
        viewTag: payment.viewTag,
        spendingPublicKey: bob.spendingPublicKey,
        viewingPrivateKey: bob.viewingPrivateKey,
        expectedStealthAddress: payment.stealthAddress,
      });
      setDerived(d);
      setScan(s);
    } catch (e) {
      fail(e, "Error derivando la clave");
    }
  }

  // Verificación visible: la address de la privkey derivada coincide con la
  // stealth address que generó Alice → Bob controla los fondos.
  const controlsFunds =
    derived !== null &&
    payment !== null &&
    addressFromPrivateKey(derived.stealthPrivateKey).toLowerCase() ===
      payment.stealthAddress.toLowerCase();

  return (
    <div className="space-y-6">
      <p className="text-sm text-slate-400">
        Las <em>stealth addresses</em> (ERC-5564 / ERC-6538) permiten que alguien
        te pague a una dirección nueva y descorrelacionada en cada pago, que solo
        vos podés vincular a tu identidad. Es la otra mitad de un pago privado:
        el pool oculta el monto/origen; las stealth addresses ocultan el destino.
        <br />
        <span className="text-slate-500">
          Toda la criptografía de abajo corre <strong>local en tu navegador</strong>.
          El registro/anuncio on-chain es opcional.
        </span>
      </p>

      {/* ============ 1) Receptor (Bob) ============ */}
      <section className="rounded-lg border border-slate-800 bg-slate-900/40 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono text-indigo-400 border border-indigo-500/40 rounded px-1.5 py-0.5">
            1 · Receptor
          </span>
          <span className="text-sm font-medium text-slate-200">
            Bob genera su meta-address
          </span>
        </div>
        <p className="text-xs text-slate-500">
          Bob crea dos pares de claves (gasto + visualización). Publica solo el
          meta-address (66 bytes, ambas pubkeys). Con eso, cualquiera puede
          pagarle sin poder correlacionar sus pagos.
        </p>

        <button
          onClick={handleGenerateMeta}
          className="w-full py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-semibold transition-colors cursor-pointer text-sm"
        >
          {bob ? "Generar otro meta-address" : "Generar meta-address"}
        </button>

        {bob && (
          <div className="space-y-3">
            <div className="text-xs text-slate-500 space-y-1">
              <div className="text-slate-400 mb-1">Meta-address (público):</div>
              <div className="font-mono text-xs break-all bg-slate-900/70 rounded p-3 text-slate-200 select-all">
                {bob.metaAddress}
              </div>
            </div>

            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-3">
              <button
                onClick={() => setShowBobKeys((v) => !v)}
                className="text-xs text-amber-200 hover:text-amber-100 cursor-pointer underline"
              >
                {showBobKeys ? "Ocultar claves privadas" : "Mostrar claves privadas (demo)"}
              </button>
              <p className="text-[11px] text-amber-200/80 mt-2">
                Estas claves son de <strong>demo</strong>: viven solo en memoria y
                se pierden al recargar. Nunca uses claves generadas en una página
                web para fondos reales.
              </p>
              {showBobKeys && (
                <div className="mt-2 space-y-1 font-mono text-[11px] break-all text-amber-100/90">
                  <div>spendingPrivateKey: {bob.spendingPrivateKey}</div>
                  <div>viewingPrivateKey: {bob.viewingPrivateKey}</div>
                </div>
              )}
            </div>

            {registryConfigured() ? (
              <div className="space-y-2">
                <button
                  onClick={handleRegister}
                  disabled={registering}
                  className="w-full py-2 rounded-lg border border-indigo-500/50 text-indigo-200 hover:bg-indigo-500/10 disabled:opacity-50 disabled:cursor-not-allowed transition-colors cursor-pointer text-sm"
                >
                  {registering ? "Confirmá en la wallet…" : "Registrar en ERC6538 (opcional)"}
                </button>
                {registerTx && (
                  <a
                    href={`${EXPLORER}/tx/${registerTx}`}
                    target="_blank"
                    rel="noreferrer"
                    className="block text-xs underline text-emerald-300"
                  >
                    Registrado on-chain · ver transacción
                  </a>
                )}
              </div>
            ) : (
              <p className="text-[11px] text-slate-600">
                Registro on-chain deshabilitado: falta{" "}
                <code className="font-mono">VITE_REGISTRY_ADDRESS</code>.
              </p>
            )}
          </div>
        )}
      </section>

      {/* ============ 2) Pagador (Alice) ============ */}
      <section className="rounded-lg border border-slate-800 bg-slate-900/40 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono text-indigo-400 border border-indigo-500/40 rounded px-1.5 py-0.5">
            2 · Pagador
          </span>
          <span className="text-sm font-medium text-slate-200">
            Alice genera una stealth address
          </span>
        </div>
        <p className="text-xs text-slate-500">
          Alice pega el meta-address de Bob y genera una dirección de un solo uso
          más una <em>ephemeral pubkey</em>. Solo Bob puede vincular esa dirección
          con su meta-address.
        </p>

        <textarea
          value={metaInput}
          onChange={(e) => setMetaInput(e.target.value)}
          placeholder="0x… (meta-address del receptor, 66 bytes)"
          rows={2}
          className="w-full rounded-lg bg-slate-900/70 border border-slate-700 p-3 text-xs font-mono text-slate-200 break-all resize-none focus:outline-none focus:border-indigo-500"
        />
        {bob && (
          <button
            onClick={() => setMetaInput(bob.metaAddress)}
            className="text-xs text-slate-400 hover:text-white cursor-pointer"
          >
            ↑ Usar el meta-address de Bob (arriba)
          </button>
        )}

        <button
          onClick={handleGeneratePayment}
          className="w-full py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-semibold transition-colors cursor-pointer text-sm"
        >
          Generar stealth address
        </button>

        {payment && (
          <div className="space-y-2 text-xs">
            <div>
              <span className="text-slate-400">Stealth address (destino):</span>
              <div className="font-mono break-all bg-slate-900/70 rounded p-2 mt-1 text-emerald-200 select-all">
                {payment.stealthAddress}
              </div>
            </div>
            <div>
              <span className="text-slate-400">Ephemeral pubkey (R, se publica):</span>
              <div className="font-mono break-all bg-slate-900/70 rounded p-2 mt-1 text-slate-200 select-all">
                {payment.ephemeralPubKey}
              </div>
            </div>
            <div className="text-slate-500">
              <span className="text-slate-400">View tag:</span>{" "}
              <span className="font-mono">{viewTagToMetadata(payment.viewTag)}</span>{" "}
              <span className="text-slate-600">
                (filtro rápido para que Bob descarte anuncios ajenos)
              </span>
            </div>

            {announcerConfigured() ? (
              <div className="space-y-2 pt-1">
                <button
                  onClick={handleAnnounce}
                  disabled={announcing}
                  className="w-full py-2 rounded-lg border border-indigo-500/50 text-indigo-200 hover:bg-indigo-500/10 disabled:opacity-50 disabled:cursor-not-allowed transition-colors cursor-pointer text-sm"
                >
                  {announcing ? "Confirmá en la wallet…" : "Anunciar en ERC5564 (opcional)"}
                </button>
                {announceTx && (
                  <a
                    href={`${EXPLORER}/tx/${announceTx}`}
                    target="_blank"
                    rel="noreferrer"
                    className="block text-xs underline text-emerald-300"
                  >
                    Anunciado on-chain · ver transacción
                  </a>
                )}
              </div>
            ) : (
              <p className="text-[11px] text-slate-600 pt-1">
                Anuncio on-chain deshabilitado: falta{" "}
                <code className="font-mono">VITE_ANNOUNCER_ADDRESS</code>.
              </p>
            )}
          </div>
        )}
      </section>

      {/* ============ 3) Receptor deriva la privkey ============ */}
      <section className="rounded-lg border border-slate-800 bg-slate-900/40 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono text-indigo-400 border border-indigo-500/40 rounded px-1.5 py-0.5">
            3 · Receptor
          </span>
          <span className="text-sm font-medium text-slate-200">
            Bob deriva la clave privada
          </span>
        </div>
        <p className="text-xs text-slate-500">
          Con la ephemeral pubkey del anuncio y sus propias claves, Bob recomputa
          el mismo secreto compartido (ECDH) y deriva la <em>clave privada</em> de
          la stealth address. Eso prueba que controla los fondos ahí depositados.
        </p>

        {!bob || !payment ? (
          <p className="text-xs text-slate-600">
            Necesitás completar los pasos 1 y 2 primero.
          </p>
        ) : (
          <button
            onClick={handleDerive}
            className="w-full py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-semibold transition-colors cursor-pointer text-sm"
          >
            Derivar clave privada
          </button>
        )}

        {derived && payment && (
          <div className="space-y-2 text-xs">
            {scan && (
              <div className="text-slate-500">
                <span className="text-slate-400">Escaneo (checkStealthAddress):</span>{" "}
                {scan.isForUser ? (
                  <span className="text-emerald-300">
                    view tag OK · el anuncio es para Bob
                  </span>
                ) : (
                  <span className="text-red-300">el anuncio NO es para Bob</span>
                )}
              </div>
            )}
            <div>
              <span className="text-slate-400">Stealth private key (derivada):</span>
              <div className="font-mono break-all bg-slate-900/70 rounded p-2 mt-1 text-amber-100/90 select-all">
                {derived.stealthPrivateKey}
              </div>
            </div>
            <div
              className={`rounded-lg border p-3 ${
                controlsFunds
                  ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
                  : "border-red-500/40 bg-red-500/10 text-red-200"
              }`}
            >
              {controlsFunds ? (
                <>
                  Verificado: <span className="font-mono break-all">
                    address(privkey derivada)
                  </span>{" "}
                  == stealth address generada por Alice. Bob controla los fondos.
                </>
              ) : (
                <>La address derivada NO coincide con la de Alice.</>
              )}
            </div>
          </div>
        )}
      </section>

      {error && (
        <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300 break-words">
          {error}
        </div>
      )}
    </div>
  );
}
