// La "nota" es el secreto que el usuario guarda al depositar y necesita para
// retirar: el par (nullifier, secret). Sin la nota NO se puede reconstruir el
// commitment ni generar la prueba de retiro — los fondos quedan inaccesibles.
//
// Formato serializado (texto plano, copiable):
//   shieldedpay-note-v1-<nullifierHex>-<secretHex>
// donde cada parte es un uint256 en hex sin prefijo 0x, 64 chars.

const PREFIX = "shieldedpay-note-v1";
const FIELD_SIZE =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n;

export interface Note {
  nullifier: bigint;
  secret: bigint;
}

// Genera una nota aleatoria criptográficamente segura, con nullifier y secret
// reducidos al campo BN254 (para que sean field elements válidos del circuito).
export function generateNote(): Note {
  return {
    nullifier: randomFieldElement(),
    secret: randomFieldElement(),
  };
}

function randomFieldElement(): bigint {
  // 32 bytes aleatorios, reducidos mod FIELD_SIZE.
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let v = 0n;
  for (const b of bytes) {
    v = (v << 8n) | BigInt(b);
  }
  return v % FIELD_SIZE;
}

function toHex64(v: bigint): string {
  return v.toString(16).padStart(64, "0");
}

export function serializeNote(note: Note): string {
  return `${PREFIX}-${toHex64(note.nullifier)}-${toHex64(note.secret)}`;
}

export function parseNote(raw: string): Note {
  const s = raw.trim();
  const parts = s.split("-");
  // shieldedpay | note | v1 | <null> | <secret>  => 5 partes
  if (parts.length !== 5 || `${parts[0]}-${parts[1]}-${parts[2]}` !== PREFIX) {
    throw new Error("Nota inválida: formato desconocido.");
  }
  const nullifierHex = parts[3];
  const secretHex = parts[4];
  if (!/^[0-9a-fA-F]{1,64}$/.test(nullifierHex) || !/^[0-9a-fA-F]{1,64}$/.test(secretHex)) {
    throw new Error("Nota inválida: los valores no son hexadecimales.");
  }
  const nullifier = BigInt("0x" + nullifierHex);
  const secret = BigInt("0x" + secretHex);
  if (nullifier >= FIELD_SIZE || secret >= FIELD_SIZE) {
    throw new Error("Nota inválida: valor fuera del campo BN254.");
  }
  return { nullifier, secret };
}
