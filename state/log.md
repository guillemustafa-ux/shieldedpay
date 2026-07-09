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
