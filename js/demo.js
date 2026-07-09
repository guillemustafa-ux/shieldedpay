// Demo end-to-end: Alice le paga a Bob usando una stealth address (ERC-5564
// scheme 1). Corré con: node demo.js
//
// Flujo:
//   1. Bob genera su meta-address stealth (spending + viewing keys) y lo
//      "publica" (en la vida real: ERC6538Registry.registerKeys).
//   2. Alice lee el meta-address de Bob y genera una stealth address nueva
//      para este pago puntual.
//   3. Alice "anuncia" el pago (en la vida real: ERC5564Announcer.announce)
//      con la stealth address, la ephemeral pubkey R y el view tag.
//   4. Bob escanea anuncios: para cada uno, chequea el view tag (barato) y,
//      si matchea, deriva la stealth address completa para confirmar que es
//      un pago suyo.
//   5. Bob deriva la privkey de esa stealth address y el script ASSERTEA que
//      la address derivada de esa privkey es EXACTAMENTE la que Alice generó.

import { generateStealthMetaAddress, generateStealthAddress, checkStealthAddress, computeStealthKey } from "./stealth.js";

function log(title, obj) {
  console.log(`\n--- ${title} ---`);
  if (typeof obj === "string") {
    console.log(obj);
  } else {
    for (const [k, v] of Object.entries(obj)) {
      console.log(`  ${k}: ${v}`);
    }
  }
}

function fail(message) {
  console.error(`\nFALLO: ${message}`);
  process.exit(1);
}

console.log("=== ShieldedPay — demo stealth address (ERC-5564 scheme 1) ===");

// 1. Bob genera su meta-address y lo publica (simulado).
const bobMeta = generateStealthMetaAddress();
log("1) Bob genera su meta-address stealth", {
  spendingPublicKey: bobMeta.spendingPublicKey,
  viewingPublicKey: bobMeta.viewingPublicKey,
  metaAddress: bobMeta.metaAddress,
});
console.log("   (Bob guarda spendingPrivateKey y viewingPrivateKey en secreto)");
console.log('   -> "on-chain": ERC6538Registry.registerKeys(1, metaAddress)');

// 2. Alice genera una stealth address para pagarle a Bob.
const payment = generateStealthAddress(bobMeta.metaAddress);
log("2) Alice genera una stealth address para este pago", payment);

// 3. Alice "anuncia" el pago (evento on-chain simulado).
log("3) Alice anuncia el pago", {
  schemeId: 1,
  stealthAddress: payment.stealthAddress,
  caller: "<address de Alice>",
  ephemeralPubKey: payment.ephemeralPubKey,
  "metadata (viewTag)": "0x" + payment.viewTag.toString(16).padStart(2, "0"),
});
console.log(
  "   -> \"on-chain\": ERC5564Announcer.announce(1, stealthAddress, ephemeralPubKey, metadata=viewTag)"
);

// 4. Bob escanea el anuncio.
const scanResult = checkStealthAddress({
  ephemeralPubKey: payment.ephemeralPubKey,
  viewTag: payment.viewTag,
  spendingPublicKey: bobMeta.spendingPublicKey,
  viewingPrivateKey: bobMeta.viewingPrivateKey,
  expectedStealthAddress: payment.stealthAddress,
});
log("4) Bob escanea el anuncio", scanResult);

if (!scanResult.isForUser) {
  fail("checkStealthAddress dijo que el anuncio NO es para Bob (view tag o address no matchean)");
}
if (scanResult.stealthAddress.toLowerCase() !== payment.stealthAddress.toLowerCase()) {
  fail("la stealth address que derivo Bob no coincide con la que genero Alice");
}

// También probamos que un tercero (Carol) descarta el anuncio: o el view tag
// no le matchea, o si por mala suerte matcheara (1/256), la address derivada
// con SUS claves no coincide con la de Alice.
const carolMeta = generateStealthMetaAddress();
const carolScan = checkStealthAddress({
  ephemeralPubKey: payment.ephemeralPubKey,
  viewTag: payment.viewTag,
  spendingPublicKey: carolMeta.spendingPublicKey,
  viewingPrivateKey: carolMeta.viewingPrivateKey,
  expectedStealthAddress: payment.stealthAddress,
});
log("4b) Carol (receptor ajeno) escanea el mismo anuncio", carolScan);
if (carolScan.isForUser) {
  fail("Carol, que no es la destinataria, derivo el mismo stealth address que Bob — esto NUNCA deberia pasar");
}

// 5. Bob deriva la privkey de la stealth address.
const derived = computeStealthKey({
  ephemeralPubKey: payment.ephemeralPubKey,
  spendingPrivateKey: bobMeta.spendingPrivateKey,
  viewingPrivateKey: bobMeta.viewingPrivateKey,
});
log("5) Bob deriva la privkey de la stealth address", derived);

// ---- ASSERT final: address(privkey derivada) === stealthAddress esperado ----
if (derived.stealthAddress.toLowerCase() !== payment.stealthAddress.toLowerCase()) {
  fail(
    `la address derivada de la privkey (${derived.stealthAddress}) NO coincide con la stealth address esperada (${payment.stealthAddress})`
  );
}

console.log(`\nOK: address(privkey derivada) === stealthAddress esperado (${derived.stealthAddress})`);
console.log("=== fin demo ===");
