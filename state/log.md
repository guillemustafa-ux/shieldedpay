# ShieldedPay — Bitácora (append-only)

Registro de corridas, decisiones autónomas y bloqueos. Lo más nuevo arriba.

---

## 2026-07-09 — D0: Andamiaje

- `git init` en `C:\Users\Cript\shieldedpay` (sin remote — push público requiere OK de Guille).
- Entorno confirmado: git 2.54.0, forge 1.7.1, curva de trabajo Sepolia.
- Convenciones calcadas de botpass/yield-vault: `foundry.toml` (solc 0.8.24, invariant runs=256/depth=50, rpc+etherscan Sepolia), `.gitignore` (+ reglas ZK: ignora `circuits/build/`, `*.ptau`, `*.zkey`, `*.r1cs`, `*.wtns`; versiona el verifier), `remappings.txt`, `.github/workflows/test.yml`, `.env.example` (adaptado: sin params BotPass, con `POOL_DENOMINATION` opcional).
- `CLAUDE.md` del proyecto escrito (misión, tesis, reglas duras, entorno, ownership).
- **Decisión autónoma:** `foundry.toml` solo declara Sepolia (no Base/Arbitrum como botpass) — el proyecto es standalone y no necesita multi-red. Reversible si se quiere multi-deploy después.
- Submódulos instalados, `forge build` exit 0, commit inicial `b43bf64`. **D0 COMPLETO.**

## 2026-07-09 — D1: Fase A (stealth addresses) — COMPLETA, auditada, PAUSADA

- Delegado a subagente Sonnet; auditado y re-verificado por Fable (re-corrí todos los checks).
- **Contratos:** `src/ERC5564Announcer.sol` (announcer stateless, evento Announcement) + `src/ERC6538Registry.sol` (EIP-712 + SignatureChecker OZ, nonce anti-replay dentro del digest, error custom InvalidSignature).
- **Tests:** 25/25 verdes (7 Announcer + 16 Registry + 2 invariant con handler, 12.8k calls c/u, 0 reverts). Coverage **100%** en ambos contratos (líneas/statements/branches/funcs).
- **JS** (`js/`, @noble/secp256k1 v3 + @noble/hashes v2): `stealth.js` (scheme 1 secp256k1: metaAddress, generate, check con viewTag, computeStealthKey), `demo.js` (flujo Alice→Bob end-to-end, Carol descartada, assert address derivada == esperada, exit 0), `stealth.test.js` (10/10 verdes con `node --test`).
- **Auditoría Fable OK:** secreto ECDH simétrico correcto, P_stealth/p_stealth consistentes, address = keccak(x‖y)[12:], anti-replay del registry correcto.
- **Pendiente D1:** deploy+verify en Sepolia (requiere OK de Guille + `.env` con claves) — NO hecho, es acción externa.
- Commit checkpoint de D1: pendiente en esta corrida.

### ⏸ PAUSA (pedido de Guille). Para retomar: seguir en D2 (Fase B parte 1 — Circom/snarkjs, .ptau Hermez, circuito withdraw.circom). Ver PLAN.md.

## 2026-07-09 — D2: Fase B parte 1 (circuito ZK + trusted setup) — COMPLETA, auditada, PAUSADA

- **Circuito diseñado por Fable** (no delegado): `circuits/withdraw.circom` + `circuits/lib/merkleProof.circom`. Doble prueba de membresía (árbol de estado + árbol de asociación, mismo commitment en ambas) + nullifierHash=Poseidon(nullifier) + binding recipient/relayer/fee (patrón Tornado x*x). `levels=20`.
- **Tooling (Sonnet):** circom v2.2.3 (binario prebuilt Windows de iden3, en `.bin/`, gitignoreado), snarkjs/circomlib/circomlibjs vía npm en `circuits/`.
- **Compilación:** 10302 non-linear + 11433 linear = **21735 constraints**. Entra en 2^15.
- **Trusted setup:** `.ptau` público `powersOfTau28_hez_final_15.ptau` desde mirror oficial GCS `https://storage.googleapis.com/zkevm/ptau/` (el bucket S3 de Hermez da 403). **Verificado por hash Blake2b-512 → MATCH exacto** contra la tabla oficial del README de iden3/snarkjs. SHA256 local: `3ef2ecc5...9e7f`. (Se descartó el `powersoftau verify` completo: replay JS de >20min sin más garantía que el hash oficial.)
- **Verifier generado:** `src/verifiers/WithdrawVerifier.sol` (Groth16, 6 señales públicas, pragma >=0.7.0<0.9.0 compatible con 0.8.24, NO editado a mano — ÚNICO artefacto ZK versionado). `forge build` exit 0.
- **Harness JS reutilizable (D3/D4):** `circuits/test/merkleTree.js` (árbol sparse incremental, exporta buildTree/getMerkleProof/ZERO_VALUE/zeros/commitmentOf/nullifierHashOf/LEVELS). ZERO_VALUE = keccak256("shieldedpay") mod FIELD (nothing-up-my-sleeve, patrón Tornado).
- **Tests circuito:** `circuits/test/proveWithdraw.test.js` — 4/4 verdes (1 válido + 3 inválidos: fuera del árbol de estado, fuera del set de asociación [caso central Privacy Pools], nullifierHash falso). Re-verificado por Fable con `--test-force-exit`.
- **Fix Fable:** agregado `--test-force-exit` al script `test` de `circuits/package.json` (el pool de workers de snarkjs cuelga `node --test` sin ese flag; sin el fix `npm test` fallaba).
- **Auditoría Fable OK:** forge build verde, verifier con 6 pubsignals correcto, binding recipient/relayer/fee correcto (Groth16 liga las señales públicas a la prueba), Fase A intacta (git status: solo circuits/, src/verifiers/, .gitignore).
- Commit checkpoint D2: pendiente en esta corrida.

### ⏸ PAUSA (pedido de Guille). Para retomar: D3 (Fase B parte 2 — PrivacyPool.sol + ASP.sol integrando el verifier, tests on-chain de depósito/retiro/double-spend, deploy Sepolia con OK). El harness `circuits/test/merkleTree.js` se reutiliza para armar los árboles en los tests de Foundry (vía FFI o precomputando inputs). Ver PLAN.md.
