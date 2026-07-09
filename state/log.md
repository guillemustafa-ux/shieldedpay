# ShieldedPay — Bitácora (append-only)

Registro de corridas, decisiones autónomas y bloqueos. Lo más nuevo arriba.

---

## 2026-07-09 — D5: Documentación y posicionamiento — COMPLETA (código); pendiente solo el deploy

- **Docs escritos por Fable** (posicionamiento = dominio de diseño, no mecánico), en inglés para alcance internacional de privacy-tech (mismo criterio que el README de botpass):
  - `docs/THESIS.md` — el diferencial: mecanismo de association sets explicado, el falso dilema privacidad/compliance, tabla comparativa Tornado/Railgun/Privacy Pools/Aztec, mapeo a la narrativa 2026 (0xbow mainnet, Kohaku/EF, EIP-8182, PSE) con cifras, y sección honesta de "qué NO es".
  - `SECURITY.md` — síntesis de auditorías: verificación realizada, modelo de confianza, revisión adversarial (double-spend, reentrancy, front-run, forja de membresía, field-range), y riesgos residuales documentados (ASP centralizado, footgun fee/relayer, tamaño del anonymity set, trusted setup).
  - `README.md` — documento de venta: tabla de metadata con cifras REALES (36 tests Foundry + 4 de circuito, coverage núcleo 97–100%, 21735 constraints), diagrama ASCII de las 2 fases, tabla de contratos, sección de proving en browser, tabla de deployments (placeholders a completar post-deploy), quickstart, link a THESIS/SECURITY.
- **Coverage real medido:** ASP/ERC5564/ERC6538/PrivacyPool 100% líneas, MerkleTree 97.18%. (El `Total 61%` de forge está diluido por el verifier autogenerado + archivos de test; se cita el per-contrato, honesto.)
- **Slither NO corrido:** Python no está instalado en esta máquina (solo stub de Microsoft Store); instalarlo + solc-select sería un pozo (regla anti-loop). Documentado honestamente en SECURITY.md con el comando recomendado — no se fabrica output.
- **Estado global:** D0–D5 completas a nivel código. Lo ÚNICO pendiente son las 2 acciones externas que requieren OK de Guille: deploy a Sepolia (Fase A + Fase B, contratos verificados en Etherscan) y deploy de la dApp a Vercel. Tras el deploy: completar la tabla de deployments del README + `VITE_POOL_ADDRESS`/`VITE_ASP_ADDRESS`. Push público al repo `guillemustafa-ux/shieldedpay` también requiere OK.
- Commit D5: en esta corrida.

## 2026-07-09 — D4: dApp con proving en el browser — COMPLETA, auditada

- **dApp (Sonnet):** `frontend/dapp/` Vite+React+TS+Tailwind v4+ethers v6. Pestañas Depositar (genera nota aleatoria → commitment → deposit) y Retirar (pega nota → reconstruye árbol de eventos Deposit → **genera la prueba Groth16 EN EL BROWSER** → withdraw). Diferencial #3 del proyecto.
- **snarkjs en Vite:** cargado como script global (`window.snarkjs` desde `public/snarkjs.min.js`) porque no bundlea como ESM; circomlibjs sí como módulo con `vite-plugin-node-polyfills` (resuelve builtins de Node que romperían el proving en runtime).
- **Verificación:** `npm run build` exit 0; `npm run smoke` (script `scripts/smokeProof.mjs` que importa vía tsx el MISMO código de la dApp — merkleTree.ts + zk.ts — y genera+verifica una prueba con la wasm/zkey reales) → **PROOF OK**. La raíz del smoke = `19836...286003`, IDÉNTICA a la de D2/D3 → el camino de proving de la dApp es correcto bit-a-bit. Auditoría Fable de `zk.ts`: orden de las 6 señales correcto, addressToField correcto, exportSolidityCallData maneja G2.
- **Decisión Fable — zkey:** el proving en browser necesita la `withdraw_final.zkey` (9.6MB) servida por Vercel. La versioné con una excepción puntual en `.gitignore` (`!frontend/dapp/public/zk/withdraw_final.zkey`) en vez de CDN externo (más autocontenido/reproducible). Carpeta `public/zk/` = 12MB.
- **Addresses post-deploy:** `src/config.ts` lee `VITE_POOL_ADDRESS`/`VITE_ASP_ADDRESS` de env con fallback placeholder + banner en UI. Se completan en Vercel tras el deploy de D3 — sin tocar código.
- **Simplificación de demo (documentada en código y UI):** el ASP incluye todos los depósitos → associationRoot==root; el mecanismo de exclusión vive en los tests de contratos. Honesto, no simula compliance falso.
- **Pendiente de validación:** proving en un browser real (MetaMask+Sepolia) — no verificable en entorno headless; la evidencia objetiva es el smoke test + el polyfill que cubre el único punto de ruptura en runtime.
- Commit D4: en esta corrida.

## 2026-07-09 — D3: Fase B parte 2 (contratos on-chain del pool) — COMPLETA, auditada

- **Contratos (Sonnet, diseño Fable):** `src/PrivacyPool.sol` (deposit denominación fija + withdraw con verificación ZK), `src/ASP.sol` (Ownable, publica raíces del set limpio), `src/MerkleTreeWithHistory.sol` (árbol incremental Poseidon, port de Tornado), interfaces `IVerifier/IHasher/IASP`.
- **Poseidon on-chain:** bytecode generado con circomlibjs `poseidonContract.createCode(2)` (el MISMO Poseidon del circuito/harness JS), deployado desde bytecode con `create` assembly (patrón Tornado). Los 21 `zeros[0..20]` hardcodeados = `computeZeros(20)` del harness.
- **Tests: 36/36 verdes** (10 del pool + 23 Fase A + 3 invariant). El cross-check `test_MerkleRoot_MatchesJsHarness` PASA: raíz on-chain == JS = `19836605508004949827567185581954422785219418104893669681374008323357588286003`. `test_Withdraw_ValidProof_PaysRecipient` verifica una **prueba Groth16 REAL** on-chain. Cubiertos: double-spend, prueba inválida, association-root-no-publicada (corazón del compliance), root de estado desconocida, fee>denominación.
- **Fixtures committeados** (CI sin la .zkey de 9.6MB): `test/fixtures/poseidonBytecode.txt` (19KB) + `test/fixtures/withdraw_valid.json` (2KB, prueba real vía `groth16.exportSolidityCallData`). Generadores: `circuits/scripts/genPoseidon.js`, `genWithdrawFixture.js`.
- **Deploy script:** `script/DeployPool.s.sol` (estilo B, dry-run sin revert).
- **Auditoría Fable:**
  - ✓ CEI + nonReentrant en withdraw (marca nullifier antes de transferir); binding de prueba evita robo por front-run.
  - ✓ Orden de las 6 señales públicas correcto `[root, associationRoot, nullifierHash, recipient, relayer, fee]`; recipient/relayer como field elements.
  - **Fix Fable:** saqué `ffi = true` de foundry.toml (ningún test usa vm.ffi; en repo público es señal de alarma innecesaria). Quedó solo `fs_permissions` de lectura. Re-testeado OK.
  - **Limitación a documentar en SECURITY.md (D5):** retiro con `fee>0` y `relayer==0` deja el `fee` atrapado en el contrato. No es vuln (la prueba liga los valores, es error deliberado del usuario) e iguala/supera el comportamiento del propio Tornado. Se documenta, no se agrega código.
- **Fase A y circuito intactos** (git status verificado).
- Commit D3: en esta corrida.

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
