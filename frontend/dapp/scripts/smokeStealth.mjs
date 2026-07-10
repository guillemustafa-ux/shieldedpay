// smokeStealth.mjs — evidencia objetiva (sin browser) de que el port a TS de la
// librería de stealth addresses es correcto.
//
// Reutiliza EL MISMO código de la dApp: importa las funciones de
// src/lib/stealth.ts (vía tsx, que resuelve el .ts). Ejercita el flujo completo
// ERC-5564 scheme 1:
//   1. Bob genera su meta-address.
//   2. Alice genera una stealth address a partir de él.
//   3. Bob deriva la clave privada de esa stealth address.
//   4. Se VERIFICA que addressFromPrivateKey(computeStealthKey(...)) coincide con
//      la stealth address que generó Alice — es decir, que la privkey derivada
//      controla efectivamente la dirección destino.
// Además comprueba el escaneo (checkStealthAddress / view tag) y el rechazo de
// un tercero ajeno, replicando el demo de la Fase A.
//
// Uso:  npm run smoke:stealth   (o: npx tsx scripts/smokeStealth.mjs)

import {
  generateStealthMetaAddress,
  generateStealthAddress,
  computeStealthKey,
  checkStealthAddress,
  addressFromPrivateKey,
} from "../src/lib/stealth.ts";

function assert(cond, msg) {
  if (!cond) {
    console.error(`FALLO: ${msg}`);
    process.exit(1);
  }
}

// 1. Bob genera su meta-address.
const bob = generateStealthMetaAddress();
assert(bob.metaAddress.length === 134, "meta-address debe ser 0x + 66 bytes");
console.log("[smoke] bob.metaAddress    =", bob.metaAddress);

// 2. Alice genera una stealth address para Bob.
const payment = generateStealthAddress(bob.metaAddress);
console.log("[smoke] stealthAddress     =", payment.stealthAddress);
console.log("[smoke] ephemeralPubKey     =", payment.ephemeralPubKey);
console.log("[smoke] viewTag             =", payment.viewTag);

// 3. Bob escanea el anuncio (view tag + derivación).
const scan = checkStealthAddress({
  ephemeralPubKey: payment.ephemeralPubKey,
  viewTag: payment.viewTag,
  spendingPublicKey: bob.spendingPublicKey,
  viewingPrivateKey: bob.viewingPrivateKey,
  expectedStealthAddress: payment.stealthAddress,
});
assert(scan.isForUser, "el receptor real (Bob) deberia reconocer el anuncio");

// 4. Bob deriva la clave privada.
const derived = computeStealthKey({
  ephemeralPubKey: payment.ephemeralPubKey,
  spendingPrivateKey: bob.spendingPrivateKey,
  viewingPrivateKey: bob.viewingPrivateKey,
});
console.log("[smoke] stealthPrivateKey   =", derived.stealthPrivateKey);

// CRITERIO DURO: la address de la privkey derivada == la stealth address generada.
const addrFromPriv = addressFromPrivateKey(derived.stealthPrivateKey);
assert(
  addrFromPriv.toLowerCase() === payment.stealthAddress.toLowerCase(),
  `address(privkey derivada)=${addrFromPriv} != stealthAddress=${payment.stealthAddress}`,
);
// coherencia interna: computeStealthKey ya reporta la misma address.
assert(
  derived.stealthAddress.toLowerCase() === payment.stealthAddress.toLowerCase(),
  "computeStealthKey.stealthAddress no coincide con la generada",
);

// 5. Un tercero ajeno (Carol) NO deriva la misma stealth address.
const carol = generateStealthMetaAddress();
const carolDerived = computeStealthKey({
  ephemeralPubKey: payment.ephemeralPubKey,
  spendingPrivateKey: carol.spendingPrivateKey,
  viewingPrivateKey: carol.viewingPrivateKey,
});
assert(
  carolDerived.stealthAddress.toLowerCase() !== payment.stealthAddress.toLowerCase(),
  "un tercero ajeno NUNCA deberia derivar la stealth address del receptor real",
);

console.log("STEALTH OK");
process.exit(0);
