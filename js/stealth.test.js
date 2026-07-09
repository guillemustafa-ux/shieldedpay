// Tests (node:test) de la libreria de derivacion stealth. Correr con:
//   node --test

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  generateStealthMetaAddress,
  generateStealthAddress,
  checkStealthAddress,
  computeStealthKey,
} from "./stealth.js";

describe("generateStealthMetaAddress", () => {
  test("devuelve claves y meta-address con los largos esperados", () => {
    const meta = generateStealthMetaAddress();

    assert.equal(meta.spendingPrivateKey.length, 66); // 0x + 32 bytes
    assert.equal(meta.viewingPrivateKey.length, 66);
    assert.equal(meta.spendingPublicKey.length, 68); // 0x + 33 bytes (comprimida)
    assert.equal(meta.viewingPublicKey.length, 68);
    assert.equal(meta.metaAddress.length, 134); // 0x + 66 bytes
    assert.equal(meta.metaAddress, meta.spendingPublicKey + meta.viewingPublicKey.slice(2));
  });

  test("dos meta-addresses generadas son siempre distintas", () => {
    const a = generateStealthMetaAddress();
    const b = generateStealthMetaAddress();

    assert.notEqual(a.metaAddress, b.metaAddress);
    assert.notEqual(a.spendingPrivateKey, b.spendingPrivateKey);
  });
});

describe("round-trip: generar -> escanear -> derivar privkey", () => {
  test("el receptor real deriva una privkey cuya address matchea la stealth address generada", () => {
    const bob = generateStealthMetaAddress();
    const payment = generateStealthAddress(bob.metaAddress);

    const derived = computeStealthKey({
      ephemeralPubKey: payment.ephemeralPubKey,
      spendingPrivateKey: bob.spendingPrivateKey,
      viewingPrivateKey: bob.viewingPrivateKey,
    });

    assert.equal(derived.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
  });

  test("acepta el meta-address tanto en formato hex como objeto {spendingPublicKey, viewingPublicKey}", () => {
    const bob = generateStealthMetaAddress();

    const fromHex = generateStealthAddress(bob.metaAddress);
    const fromObj = generateStealthAddress({
      spendingPublicKey: bob.spendingPublicKey,
      viewingPublicKey: bob.viewingPublicKey,
    });

    // Direcciones distintas (cada una con su propia ephemeral key), pero
    // ambas deben poder ser derivadas correctamente por Bob.
    for (const payment of [fromHex, fromObj]) {
      const derived = computeStealthKey({
        ephemeralPubKey: payment.ephemeralPubKey,
        spendingPrivateKey: bob.spendingPrivateKey,
        viewingPrivateKey: bob.viewingPrivateKey,
      });
      assert.equal(derived.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
    }
  });

  test("round-trip se sostiene en muchas repeticiones (distintas ephemeral keys cada vez)", () => {
    const bob = generateStealthMetaAddress();

    for (let i = 0; i < 25; i++) {
      const payment = generateStealthAddress(bob.metaAddress);
      const derived = computeStealthKey({
        ephemeralPubKey: payment.ephemeralPubKey,
        spendingPrivateKey: bob.spendingPrivateKey,
        viewingPrivateKey: bob.viewingPrivateKey,
      });
      assert.equal(derived.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
    }
  });
});

describe("checkStealthAddress", () => {
  test("el receptor real: isForUser=true y la address derivada coincide", () => {
    const bob = generateStealthMetaAddress();
    const payment = generateStealthAddress(bob.metaAddress);

    const result = checkStealthAddress({
      ephemeralPubKey: payment.ephemeralPubKey,
      viewTag: payment.viewTag,
      spendingPublicKey: bob.spendingPublicKey,
      viewingPrivateKey: bob.viewingPrivateKey,
      expectedStealthAddress: payment.stealthAddress,
    });

    assert.equal(result.isForUser, true);
    assert.equal(result.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
  });

  test("un receptor ajeno con viewTag equivocado es descartado sin derivar address", () => {
    const bob = generateStealthMetaAddress();
    const carol = generateStealthMetaAddress();
    const payment = generateStealthAddress(bob.metaAddress);

    // Forzamos un viewTag que casi seguro no matchea el de Carol para este pago.
    const wrongViewTag = (payment.viewTag + 1) % 256;

    const result = checkStealthAddress({
      ephemeralPubKey: payment.ephemeralPubKey,
      viewTag: wrongViewTag,
      spendingPublicKey: carol.spendingPublicKey,
      viewingPrivateKey: carol.viewingPrivateKey,
    });

    assert.equal(result.isForUser, false);
    assert.equal(result.stealthAddress, null);
  });

  test("una privkey ajena NO deriva la stealth address del receptor real, aunque el viewTag matchee", () => {
    const bob = generateStealthMetaAddress();
    const payment = generateStealthAddress(bob.metaAddress);

    // Carol arma un "meta-address" propio pero fuerza spendingPublicKey de bob
    // para simular un atacante que sabe P_spend de Bob (pública) pero NO su
    // viewing privkey. Sin la viewing privkey correcta, el secreto compartido
    // que calcula es otro, así que el view tag no matchea case general;
    // igualmente, aunque coincidiera el view tag, la derivación de address da
    // otro resultado con la privkey de vista incorrecta.
    const carol = generateStealthMetaAddress();

    const result = checkStealthAddress({
      ephemeralPubKey: payment.ephemeralPubKey,
      viewTag: payment.viewTag,
      spendingPublicKey: bob.spendingPublicKey,
      viewingPrivateKey: carol.viewingPrivateKey, // viewing key incorrecta
      expectedStealthAddress: payment.stealthAddress,
    });

    // O bien el viewTag no matchea (se descarta), o si matcheara por azar
    // (1/256), la address derivada NO puede coincidir con la real.
    if (result.isForUser) {
      assert.notEqual(result.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
    } else {
      assert.equal(result.stealthAddress, null);
    }
  });
});

describe("computeStealthKey — privkey ajena no sirve", () => {
  test("la privkey derivada por un receptor incorrecto NO produce la stealth address real", () => {
    const bob = generateStealthMetaAddress();
    const mallory = generateStealthMetaAddress();
    const payment = generateStealthAddress(bob.metaAddress);

    const wrongDerivation = computeStealthKey({
      ephemeralPubKey: payment.ephemeralPubKey,
      spendingPrivateKey: mallory.spendingPrivateKey,
      viewingPrivateKey: mallory.viewingPrivateKey,
    });

    assert.notEqual(wrongDerivation.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
  });
});

describe("fuzz liviano: muchos pares (meta-address, pago) distintos", () => {
  test("round-trip completo + rechazo de terceros se sostiene en N iteraciones aleatorias", () => {
    for (let i = 0; i < 15; i++) {
      const receiver = generateStealthMetaAddress();
      const outsider = generateStealthMetaAddress();
      const payment = generateStealthAddress(receiver.metaAddress);

      // El receptor real siempre puede confirmar y derivar.
      const scan = checkStealthAddress({
        ephemeralPubKey: payment.ephemeralPubKey,
        viewTag: payment.viewTag,
        spendingPublicKey: receiver.spendingPublicKey,
        viewingPrivateKey: receiver.viewingPrivateKey,
        expectedStealthAddress: payment.stealthAddress,
      });
      assert.equal(scan.isForUser, true, `iter ${i}: el receptor real deberia poder confirmar el pago`);

      const derived = computeStealthKey({
        ephemeralPubKey: payment.ephemeralPubKey,
        spendingPrivateKey: receiver.spendingPrivateKey,
        viewingPrivateKey: receiver.viewingPrivateKey,
      });
      assert.equal(derived.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());

      // Un tercero ajeno nunca deriva la misma stealth address con SU privkey.
      const outsiderDerivation = computeStealthKey({
        ephemeralPubKey: payment.ephemeralPubKey,
        spendingPrivateKey: outsider.spendingPrivateKey,
        viewingPrivateKey: outsider.viewingPrivateKey,
      });
      assert.notEqual(outsiderDerivation.stealthAddress.toLowerCase(), payment.stealthAddress.toLowerCase());
    }
  });
});
