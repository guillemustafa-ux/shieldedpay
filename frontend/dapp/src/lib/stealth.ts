// Derivación off-chain de stealth addresses — ERC-5564 scheme 1 (secp256k1).
//
// Port a TypeScript (browser) de la librería de la Fase A `js/stealth.js`.
// Usa exactamente las mismas dependencias (@noble/secp256k1 v3 + @noble/hashes v2)
// y la misma lógica, así que produce resultados IDÉNTICOS a la lib original.
//
// Este módulo NO toca la blockchain: los contratos (ERC5564Announcer,
// ERC6538Registry) solo guardan/emiten bytes opacos. Toda la criptografía
// (ECDH, derivación de claves, cómputo de la address) corre acá, en el cliente.
//
// Diseño (scheme 1):
//   - Meta-address del receptor = (P_spend, P_view), dos pubkeys comprimidas.
//   - Pagador genera un privkey efímero r -> R = r·G (se publica junto al pago).
//   - Secreto compartido: s = keccak256(serialize(r·P_view))  (ECDH).
//   - Pubkey stealth:      P_stealth = P_spend + s·G
//   - Address stealth:     últimos 20 bytes de keccak256(x || y) de P_stealth.
//   - View tag:            primer byte de keccak256(s) — filtro rápido de escaneo.
//   - Receptor recomputa el mismo `s` vía p_view·R (== r·P_view) y deriva la
//     privkey stealth: p_stealth = (p_spend + s) mod n.

import * as secp from "@noble/secp256k1";
import { keccak_256 } from "@noble/hashes/sha3.js";
import { bytesToHex, hexToBytes, concatBytes } from "@noble/hashes/utils.js";

const N = secp.Point.CURVE().n; // orden del grupo secp256k1

// ---- tipos ----

export interface StealthMetaAddress {
  spendingPrivateKey: string;
  spendingPublicKey: string;
  viewingPrivateKey: string;
  viewingPublicKey: string;
  metaAddress: string;
}

export interface StealthPayment {
  stealthAddress: string;
  ephemeralPubKey: string;
  viewTag: number;
}

export interface ScanResult {
  isForUser: boolean;
  stealthAddress: string | null;
}

export interface DerivedKey {
  stealthPrivateKey: string;
  stealthAddress: string;
}

type HexOrBytes = string | Uint8Array;

// ---- helpers de formato ----

/** Normaliza un string hex (con o sin "0x") a Uint8Array. */
function toBytes(hexOrBytes: HexOrBytes): Uint8Array {
  if (hexOrBytes instanceof Uint8Array) return hexOrBytes;
  const hex = hexOrBytes.startsWith("0x") ? hexOrBytes.slice(2) : hexOrBytes;
  return hexToBytes(hex);
}

/** Uint8Array -> "0x..." */
function toHex(bytes: Uint8Array): string {
  return "0x" + bytesToHex(bytes);
}

/** bigint -> 32 bytes big-endian (para privkeys/scalars). */
function scalarToBytes32(scalar: bigint): Uint8Array {
  return hexToBytes(scalar.toString(16).padStart(64, "0"));
}

/** bigint mod n, siempre no-negativo. */
function mod(a: bigint, n: bigint = N): bigint {
  const r = a % n;
  return r >= 0n ? r : r + n;
}

/**
 * Deriva una dirección Ethereum a partir de un punto de la curva (pubkey sin
 * comprimir): últimos 20 bytes de keccak256(x || y), 32 bytes cada uno.
 */
function addressFromPoint(point: secp.Point): string {
  const uncompressed = point.toBytes(false); // 0x04 || x(32) || y(32)
  const xy = uncompressed.slice(1); // sacamos el prefijo 0x04
  const hash = keccak_256(xy);
  return toHex(hash.slice(12)); // últimos 20 bytes
}

/**
 * Secreto compartido ECDH: hash del punto (privScalarBytes · pubPointBytes),
 * en formato comprimido. Simétrico: r·P_view == p_view·R.
 */
function sharedSecretHash(privKeyBytes: Uint8Array, pubKeyBytes: Uint8Array): Uint8Array {
  const sharedPoint = secp.getSharedSecret(privKeyBytes, pubKeyBytes, true); // 33 bytes comprimidos
  return keccak_256(sharedPoint); // 32 bytes: este es "s" (como bytes)
}

/** View tag = primer byte de keccak256(s). */
function viewTagFromS(sBytes: Uint8Array): number {
  return keccak_256(sBytes)[0];
}

/**
 * Deriva la dirección Ethereum de una clave privada (hex "0x" de 32 bytes).
 * Se usa para verificar de forma independiente que la privkey derivada por el
 * receptor controla efectivamente la stealth address.
 */
export function addressFromPrivateKey(privateKey: HexOrBytes): string {
  const pubKey = secp.getPublicKey(toBytes(privateKey), false);
  return addressFromPoint(secp.Point.fromBytes(pubKey));
}

// ---- API pública ----

/**
 * Genera un meta-address stealth nuevo: dos keypairs independientes (spending y
 * viewing). El meta-address serializado (P_spend || P_view, comprimidas,
 * 33+33=66 bytes) es lo que se registraría on-chain en
 * ERC6538Registry.registerKeys(schemeId=1, stealthMetaAddress).
 */
export function generateStealthMetaAddress(): StealthMetaAddress {
  const spendingPrivateKey = secp.utils.randomSecretKey();
  const viewingPrivateKey = secp.utils.randomSecretKey();

  const spendingPublicKey = secp.getPublicKey(spendingPrivateKey, true);
  const viewingPublicKey = secp.getPublicKey(viewingPrivateKey, true);

  const metaAddressBytes = concatBytes(spendingPublicKey, viewingPublicKey);

  return {
    spendingPrivateKey: toHex(spendingPrivateKey),
    spendingPublicKey: toHex(spendingPublicKey),
    viewingPrivateKey: toHex(viewingPrivateKey),
    viewingPublicKey: toHex(viewingPublicKey),
    // bytes crudos (66 bytes) tal como se registran en ERC6538Registry.
    metaAddress: toHex(metaAddressBytes),
  };
}

/**
 * Lado pagador: dado el meta-address del receptor (hex "0x" de 66 bytes, o un
 * objeto {spendingPublicKey, viewingPublicKey} en hex), genera una nueva stealth
 * address de un solo uso.
 */
export function generateStealthAddress(
  metaAddress: string | { spendingPublicKey: HexOrBytes; viewingPublicKey: HexOrBytes },
): StealthPayment {
  const { spendingPublicKey, viewingPublicKey } = parseMetaAddress(metaAddress);

  // Privkey efímera del pagador, descartable: solo sirve para este pago.
  const ephemeralPrivateKey = secp.utils.randomSecretKey();
  const ephemeralPubKey = secp.getPublicKey(ephemeralPrivateKey, true);

  const sBytes = sharedSecretHash(ephemeralPrivateKey, viewingPublicKey); // s = keccak256(r·P_view)
  const sScalar = mod(BigInt(toHex(sBytes)));
  if (sScalar === 0n) {
    // Probabilidad ~2^-256: por completitud, no seguimos con un secreto nulo.
    throw new Error("shared secret nulo (reintentar con otra privkey efimera)");
  }

  const spendPoint = secp.Point.fromBytes(spendingPublicKey);
  const stealthPoint = spendPoint.add(secp.Point.BASE.multiply(sScalar)); // P_stealth = P_spend + s·G

  return {
    stealthAddress: addressFromPoint(stealthPoint),
    ephemeralPubKey: toHex(ephemeralPubKey),
    viewTag: viewTagFromS(sBytes),
  };
}

/**
 * Lado receptor (escaneo): dados R (ephemeralPubKey) y el viewTag de un anuncio,
 * más las claves propias del receptor, determina si el anuncio es para él sin
 * recalcular la stealth pubkey completa cuando el viewTag no matchea.
 */
export function checkStealthAddress({
  ephemeralPubKey,
  viewTag,
  spendingPublicKey,
  viewingPrivateKey,
  expectedStealthAddress,
}: {
  ephemeralPubKey: HexOrBytes;
  viewTag: number;
  spendingPublicKey: HexOrBytes;
  viewingPrivateKey: HexOrBytes;
  expectedStealthAddress?: string;
}): ScanResult {
  const R = toBytes(ephemeralPubKey);
  const p_view = toBytes(viewingPrivateKey);
  const P_spend = toBytes(spendingPublicKey);

  const sBytes = sharedSecretHash(p_view, R); // s = keccak256(p_view·R) == keccak256(r·P_view)
  const computedViewTag = viewTagFromS(sBytes);

  if (computedViewTag !== viewTag) {
    // Filtro barato: descartamos sin derivar la pubkey completa.
    return { isForUser: false, stealthAddress: null };
  }

  const sScalar = mod(BigInt(toHex(sBytes)));
  const spendPoint = secp.Point.fromBytes(P_spend);
  const stealthPoint = spendPoint.add(secp.Point.BASE.multiply(sScalar));
  const derivedAddress = addressFromPoint(stealthPoint);

  const isForUser = expectedStealthAddress
    ? derivedAddress.toLowerCase() === expectedStealthAddress.toLowerCase()
    : true;

  return { isForUser, stealthAddress: derivedAddress };
}

/**
 * Lado receptor (derivación de clave): dado R y las claves privadas propias del
 * receptor, calcula la privkey de la stealth address:
 *   p_stealth = (p_spend + s) mod n
 */
export function computeStealthKey({
  ephemeralPubKey,
  spendingPrivateKey,
  viewingPrivateKey,
}: {
  ephemeralPubKey: HexOrBytes;
  spendingPrivateKey: HexOrBytes;
  viewingPrivateKey: HexOrBytes;
}): DerivedKey {
  const R = toBytes(ephemeralPubKey);
  const p_spend = toBytes(spendingPrivateKey);
  const p_view = toBytes(viewingPrivateKey);

  const sBytes = sharedSecretHash(p_view, R);
  const sScalar = mod(BigInt(toHex(sBytes)));

  const stealthPrivScalar = mod(BigInt(toHex(p_spend)) + sScalar);
  const stealthPrivateKeyBytes = scalarToBytes32(stealthPrivScalar);

  // Verificación interna: la pubkey derivada de la privkey stealth SIEMPRE tiene
  // que dar la misma address que calcularíamos vía P_spend + s·G.
  const stealthPubKey = secp.getPublicKey(stealthPrivateKeyBytes, false);
  const point = secp.Point.fromBytes(stealthPubKey);
  const stealthAddress = addressFromPoint(point);

  return {
    stealthPrivateKey: toHex(stealthPrivateKeyBytes),
    stealthAddress,
  };
}

/**
 * Acepta un meta-address como hex "0x" de 66 bytes (P_spend || P_view
 * comprimidas) o como objeto {spendingPublicKey, viewingPublicKey} en hex.
 */
export function parseMetaAddress(
  metaAddress: string | { spendingPublicKey: HexOrBytes; viewingPublicKey: HexOrBytes },
): { spendingPublicKey: Uint8Array; viewingPublicKey: Uint8Array } {
  if (typeof metaAddress === "string") {
    const bytes = toBytes(metaAddress.trim());
    if (bytes.length !== 66) {
      throw new Error(`metaAddress hex invalido: se esperaban 66 bytes, vinieron ${bytes.length}`);
    }
    return {
      spendingPublicKey: bytes.slice(0, 33),
      viewingPublicKey: bytes.slice(33, 66),
    };
  }
  return {
    spendingPublicKey: toBytes(metaAddress.spendingPublicKey),
    viewingPublicKey: toBytes(metaAddress.viewingPublicKey),
  };
}
