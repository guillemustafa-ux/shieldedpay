# ShieldedPay — Bitácora (append-only)

Registro de corridas, decisiones autónomas y bloqueos. Lo más nuevo arriba.

---

## 2026-07-10 — dApp integrada al pool multi-ASP con selector de ASP ("hacelo")

- Guille: "hacelo" (sobre integrar la dApp al multi-ASP para que la UI muestre la elección de ASP). Cambio de frontend hecho por Fable directamente (no subagente).
- **`config.ts`**: DEFAULT_POOL → PrivacyPoolMultiASP `0xa84dbB14...`, nuevo `ASP_REGISTRY_ADDRESS` `0x31e8819d...` + `ASP_REGISTRY_ABI` (nextAspId/asps/isActive/isKnownRoot), `POOL_ABI.withdraw` con `aspId` (10 args). **`lib/pool.ts`**: `getRegistry()` + `fetchAsps()` (enumera ids 1..nextAspId-1 con owner/stake/slashed/active/latestRoot). **`WithdrawTab.tsx`**: selector de ASP (lista real del registry on-chain; los SLASHED se muestran y NO se pueden elegir), valida `isKnownRoot(aspId, associationRoot)` ANTES de probar (feedback claro), pasa `aspId` al withdraw. **`App.tsx`**: nota de UI reencuadrada (registry con staking+slashing; simplificación assoc==state explícita). vite-env.d.ts actualizado.
- **Limitación honesta documentada en la UI:** la dApp usa assoc==state (todos los depósitos = set limpio), así que el selector demuestra la MECÁNICA (elegís ASP → aspId → el pool valida contra ese ASP; un slashed no es elegible) pero no sets de asociación distintos por ASP (eso vive en los tests de contratos).
- **Verificación objetiva:** `npm run build` (tsc --noEmit + vite build) VERDE, sin errores de tipos. Sin referencias huérfanas a getASP/ASP_ADDRESS/ASP_ABI.
- **Demo self-service sembrada on-chain:** se depositó una nota con secreto conocido (nullifier=42, secret=4242 → commitment vía Poseidon), la nueva state root `R5=17229411...` la publicó el ASP honesto #2, `isKnownRoot(2,R5)=true`. La nota (`shieldedpay-note-v1-...02a-...1092`) está en el README para que un visitante ejerza el retiro ZK completo desde la dApp eligiendo el ASP #2.
- Balance final 0.0069 ETH. Commit + push. Vercel auto-deployó (commit e68589c Ready); Guille verificó el selector en vivo (ASP #1 Slashed stake 0.0 root 0x3e7=999, ASP #2 Activo).
- **FIX post-deploy (commit c833cc3):** el retiro desde la dApp fallaba con `range 11246681 exceeds limit of 10000` — `fetchDeposits` pedía eventos Deposit desde bloque 0 a latest en UNA consulta y muchos RPCs limitan eth_getLogs a ~10k bloques (bug heredado del pool original). Fix: `POOL_DEPLOY_BLOCK=11246403` en config + `fetchDeposits` pagina en tramos de 9000 bloques. Build verde. **Lección:** nunca `queryFilter(filter, 0, "latest")` en dApp; arrancar en el bloque de deploy y paginar.

## 2026-07-10 — ASP descentralizado DEPLOYADO en Sepolia + demos reales on-chain ("todo lo quiero onchain")

- Guille: "todo lo quiero onchain". Se llevó el ASP descentralizado de tested a **evidencia on-chain citable**. Deploy con `script/DeployMultiASP.s.sol`, ejecución supervisada tx-por-tx por Fable (balance ajustado 0.0249 ETH → decisiones de gas reales, no delegado).
- **Optimización de gas necesaria:** el dry-run pedía 0.0261 ETH (> balance) porque redeployaba el Poseidon hasher + verifier Groth16 (bytecode grande). Se modificó el script (cambio quirúrgico) para **reutilizar hasher/verifier ya deployados vía env** (`HASHER_ADDRESS`/`VERIFIER_ADDRESS`, default address(0)=deploya fresh). Bajó a 0.0178 ETH. Reusa Poseidon `0x4823D77f...` + Verifier `0x89E117f1...` (idénticos, ya verificados).
- **3 contratos nuevos DEPLOYADOS Y VERIFICADOS** (stake mínimo bajado a 0.0002 ETH por env para demos baratas): FlaggedRegistry `0x3213497CE314ffd784837e082F2752A7617AfbAD`, ASPRegistry `0x31e8819d87EFf6b851Fc904b148022dFC70f31D3`, PrivacyPoolMultiASP `0xa84dbB140CF7d3cD0710E941D86Fc1969A89EA46` (governance/attester = deployer).
- **Fraud proof REAL (la joya):** ASP deshonesto (aspId=1) registró + publicó un set degenerado de 1 hoja; `challengeDegenerate` lo slasheó → `isActive=false`, `stake=0`, evento `ASPSlashedByFraud` con reward `0.0001 ETH` (50% exacto) al challenger, sin governance. tx `0x4d759e0217ae7c4aa46cd0a75fd6f7dad4797a3e9266acb4137f1ff80b7827ae`.
- **Retiro ZK REAL contra el pool multi-ASP:** se depositaron los 4 commitments del fixture (el `getLastRoot()` on-chain coincidió **bit-a-bit** con `fxRoot`), ASP honesto (aspId=2) publicó la associationRoot real, y la **MISMA prueba Groth16** del fixture verificó seleccionando `aspId=2` → relayer cobró el fee (0.001 ETH), nullifier gastado. Prueba on-chain de que la descentralización NO toca la criptografía. tx `0xbb5bb8ffe272a981bc54744f2ca309c79ec33d2ba7ef50c53c544ff992b39c3f`.
- Balance final 0.0088 ETH (gasto total del ejercicio ~0.016). README (nueva subsección "Decentralized ASP — also live" con tabla + las 2 txs) y SECURITY (residual risk reencuadrado a deployed) actualizados. Commit + push con OK.

## 2026-07-10 — Layer 1: fraud proof de permisividad (rule-violation) — diseño Fable / ejecución Sonnet, auditado

- Guille pidió "Layer 1": el tercer fraud proof, que cierra el negativo que faltaba. Los dos previos (integrity, degenerate) prueban que la root ES el Merkle del set comprometido y que el set no desanonimiza; faltaba probar que ese set **no incluye commitments que las reglas dicen excluir** (permisividad).
- **`src/FlaggedRegistry.sol`** (nuevo, Ownable) — colapso on-chain del RESULTADO del taint analysis de Layer 1 (la propagación sobre el grafo NO es recomputable on-chain → un attester la corre off-chain y publica qué commitments quedaron marcados). `isFlagged` mapping + `flag`/`flagBatch`/`unflag`, todos `onlyOwner`. `unflag` modela la ventana de disputa de Layer 4. **`src/interfaces/IFlaggedRegistry.sol`** — el registry sólo consume `isFlagged(commitment)`.
- **`ASPRegistry.sol`**: constructor toma `IFlaggedRegistry` inmutable (ahora 4 args); nuevo **`challengeInclusion(aspId, root, set, flaggedIndex)`** — verifica keccak(set)==dataHash (no se puede framear), que `flaggedIndex` apunte a una hoja marcada en el FlaggedRegistry → el ASP fue permisivo → `_slashByFraud` (reutiliza el patrón CEI+nonReentrant existente). NO recomputa el Merkle: integrity ya garantiza root==Merkle(set), así que juntos cierran que el árbol real no contiene marcados sin dejar al ASP slasheable.
- **Verificación (auditada por Fable):** 71 tests verdes (62 + 9 nuevos: slash exitoso + rechazos sin-marcados/índice-limpio/keccak-mismatch/índice-fuera-de-rango/root-no-publicada + access control de flag/unflag). Cross-check de complementariedad: un ASP que publica root de un set sucio pero dataHash de uno limpio cae por **integrity**, no escapa. Snapshot regenerado (CI corre `forge snapshot --check`). Desvío necesario auditado: se tocó `test/PrivacyPoolMultiASP.t.sol` (constructor de 4 args en su setUp) — quirúrgico, demo original/circuito/dApp intactos.
- **Futuro documentado** (limitaciones #4/#5/#6 en cabecera de ASPRegistry + DECENTRALIZED-ASP.md): censura/exclusión-indebida no slasheable (se maneja por exit multi-ASP), taint propagation no recomputable on-chain (se confía en el attester/disputas), attester único (la generalización a políticas por-ASP es Layer 4).
- Commit local en esta corrida. **Push al repo público: pendiente OK de Guille.**

## 2026-07-10 — Fraud-proof slashing verificable (Layer 5 real del ASP) — diseño Fable / ejecución Sonnet, auditado

- Contexto: ShieldedPay ya está DESPLEGADO y publicado (Sepolia, 6 contratos verificados, retiro ZK E2E real; ver README + memoria project_shieldedpay). Guille pidió "lo más pesado": convertir el slashing del ASPRegistry de stub de governance a **fraud proof verificable on-chain** (lo más difícil del diseño DECENTRALIZED-ASP, Layer 5).
- **`src/lib/PoseidonMerkleLib.sol`** (nuevo) — recomputación on-chain del sparse Merkle root Poseidon, réplica 1:1 de `buildTree` del harness JS (21 zeros hardcodeados, valida hojas en el campo). **Cross-check duro:** `computeRoot([c0,c1,c2])` == la associationRoot del fixture, bit-a-bit → sirve de testigo en el fraud proof.
- **`ASPRegistry.sol`** evolucionado: constructor toma `IHasher`; guarda `rootDataHash[aspId][root]`; `MIN_SET_SIZE=2`; `challengeIntegrity(aspId, root, set)` — verifica keccak(set)==dataHash, recomputa el root y si != publicado → slash (el ASP mintió sobre su propia root); `challengeDegenerate` — slashea sets < MIN_SET_SIZE (desanonimizan); `_slashByFraud` con **50% del stake al challenger** (bounty para watchtowers; retener el otro 50% mata el auto-slash colusivo), CEI + nonReentrant. Un ASP honesto es INSLASHEABLE; no se puede framear (keccak). `slash()` onlyOwner queda como backup de emergencia documentado.
- **Verificación (auditada por Fable):** 62 tests verdes (54 + 8 de fraude). `_slashByFraud` con CEI estricto (slashed + stake=0 antes de transferir) y doble barrera de reentrancy. Gas snapshot regenerado (el CI del repo público corre `forge snapshot --check`).
- **Futuro documentado** (DECENTRALIZED-ASP.md): data-withholding (negativo no probable on-chain → challenge-response de revelación) y fraud proof sucinto para sets grandes (hoy recomputa todo, O(n) Poseidon).
- Commit local en esta corrida. **Push al repo público: pendiente OK de Guille** (repo ya es público).

## 2026-07-10 — Slice vertical: ASP registry multi-ASP (diseño Fable / ejecución Sonnet) — auditado

- Guille pidió pasar de diseño a código: construir el ASP registry del DECENTRALIZED-ASP.md como slice vertical. Diseño Fable (spec cerrado), ejecución Sonnet. **Archivos nuevos, demo original INTACTO** (PrivacyPool.sol/ASP.sol sin tocar).
- **`src/ASPRegistry.sol`** — Layer 3 completo + stub Layer 5: `register()` con MIN_STAKE, `publishRoot()` con historial circular por-ASP (30), `isActive()`/`isKnownRoot()`, `slash()` (governance stub). **`src/PrivacyPoolMultiASP.sol`** — pool que consume el registry: withdraw toma `aspId` extra y valida `registry.isActive(aspId) && registry.isKnownRoot(aspId, associationRoot)` (el circuito/prueba NO cambian; aspId es selector on-chain, no señal ZK). `src/interfaces/IASPRegistry.sol`, `script/DeployMultiASP.s.sol`.
- **54/54 tests verdes** (37 previos intactos + 17 nuevos: 10 del registry + 7 del pool multiASP). Corazón: `test_Withdraw_ValidProof_AspSelected_PaysRecipient` — la MISMA prueba Groth16 real del fixture verifica contra el pool multi-ASP igual que contra el original → el cambio a registry NO tocó la criptografía. Rechazos: ASP inexistente, no-publicó-esa-root, slashed, double-spend, fee/relayer.
- **Auditoría Fable:** `isKnownRoot` (loop circular por-ASP) correcto — recorre los 30 slots una vez, rechaza root=0 y ASP inexistente, sin falsos positivos. Control de acceso OK (publishRoot solo owner del ASP, slash solo governance). Sin superficie de reentrancy. Stubs bien documentados (slashing por governance, DA no validada, minSetSize) — el fraud-proof real es futuro.
- **Cierra el loop diseño→código:** DECENTRALIZED-ASP.md actualizado marcando que el PoC de Layer 3+5-stub existe y está testeado.
- Commit slice: en esta corrida.
## 2026-07-10 — docs/DECENTRALIZED-ASP.md: diseño de un ASP descentralizado (trabajo Fable 5, elegido por Guille)

- Guille pidió otra tarea de estructura pesada; eligió (de 3 opciones) "componente sobre el pool compartido" — coherente con la recomendación build-vs-integrate de ARCHITECTURE.md.
- **`docs/DECENTRALIZED-ASP.md`** — blueprint del componente MÁS difícil y menos resuelto de Privacy Pools: descentralizar el Association Set Provider (hoy un Ownable / un operador central, incluso en 0xbow). Diseño en **5 capas** (construcción determinista del set por taint sobre el grafo público / data availability IPFS-Arweave-blobs / registry on-chain multi-ASP con root history / governance del flagging vía reglas públicas + attestations EAS + disputas / accountability con staking-slashing-reputación), flujo de usuario (elegir ASP), interfaz `IASPRegistry` (cambio de 2 líneas en el pool, circuito INTACTO), roadmap de descentralización progresiva, threat model específico, relación con EIP-8182/PSE/0xbow, y sección honesta de problemas abiertos (censura no-slashable, "dirty" objetivo, DA a escala, fragmentación del anonymity set).
- Insight de arquitectura clave: la descentralización vive en QUÉ roots honra el pool (un registry lookup), NO en el circuito ZK — la criptografía difícil queda intacta. Linkeado desde ARCHITECTURE.md.
- Es exactamente "el pedazo que un protocolo de privacy contrataría diseñar". Trabajo Fable puro, no delegado.
- Commit: en esta corrida.

## 2026-07-09 — docs/ARCHITECTURE.md: diseño "de la demo a producción" (trabajo Fable 5, no delegado)

- Guille pidió aprovechar Fable 5 en "algo pesado de estructura" mientras vuelve. Elegí un documento de arquitectura senior (diseño puro, no ejecución → no se delega a Sonnet), que suma sin ensuciar el código (no es sobre-ingeniería: es diseño documentado, honesto sobre qué falta).
- **`docs/ARCHITECTURE.md`** — las 4 fronteras estructurales de la demo (ASP, denominación, relayer, trusted setup) + 6 ejes de diseño a producción, cada uno con problema/opciones/trade-offs/recomendación opinada: (1) ASP multi-proveedor elegido por el usuario, (2) denominación fija vs shielded balances (fork que define qué ES el proyecto), (3) relayers → account abstraction/paymaster, (4) Groth16 vs universal setup/Noir según tasa de cambio del circuito, (5) scaling/L2/EIP-8182, (6) governance/upgradeability. Sección clave: **build vs integrate** — el argumento honesto de que lo senior es construir SOBRE el pool compartido del ecosistema (Privacy Pools/EIP-8182), no un pool standalone que fragmenta el anonymity set. Roadmap secuenciado + deltas de threat model para producción.
- Linkeado desde el README (junto a THESIS). Muestra criterio de sistemas, no solo tutorial — señal senior para un revisor de privacy.
- Commit: en esta corrida. (ShieldedPay a nivel código sigue COMPLETO; el deploy sigue esperando el `.env` de Guille — ver DEPLOY.md.)

## 2026-07-09 — Refuerzo D: reproducibilidad ZK + CI de la dApp (diseño Fable / ejecución Sonnet) — auditado

- **`circuits/README.md`** — doc técnico del circuito (qué prueba, layout) + **cómo regenerar el pipeline de cero** paso a paso, y —lo clave— la sección de reproducibilidad honesta: r1cs/wasm DETERMINISTA (21735 constraints recompilable por cualquiera) vs zkey/verifier NO determinista (entropía de fase 2 → el verifier versionado es UNO de infinitos válidos; incluye el flujo para que un revisor regenere el suyo y confirme que los tests pasan). Esto es lo que le faltaba al repo para ser una pieza ZK auditable/reproducible.
- **`circuits/scripts/build.sh`** — helper idempotente: baja circom v2.2.3 (release iden3 `circom-windows-amd64.exe`) si falta, compila el circuito, y valida por `snarkjs r1cs info` que sean **21735 constraints** (exit≠0 si no matchea). No regenera zkey/verifier.
- **`.github/workflows/dapp.yml`** — CI nuevo: `npm ci && npm run build` en frontend/dapp (node 20, hardening `permissions:{}` + `contents:read`, calca test.yml). Cubre el build de la dApp que el CI de Foundry no tocaba.
- **Fix Fable (correctness):** el agente detectó que `npm test` de circuits/ estaba roto en **Node 24** (el script pasaba `test/` directorio pelado, que Node 24 ya no resuelve como raíz). Correctamente no tocó package.json (fuera de su entregable) y me lo dejó. Cambié el script a `node --test --test-force-exit "test/*.test.js"` → 4/4 verdes en Node 24.
- **Auditoría Fable (re-corrida por mí):** `bash circuits/scripts/build.sh` → 21735 constraints exit 0; `forge build` exit 0; `npm test` (circuits) 4/4; `npm run build` (dapp) exit 0; dapp.yml bien formado. README técnicamente correcto.
- Commit refuerzo D: en esta corrida (dominio circuits/ + .github/ + fix package.json).

## 2026-07-09 — Refuerzo C: tab de stealth en la dApp (diseño Fable / ejecución Sonnet) — auditado

- **Diferencial #2 cerrado:** la dApp ahora tiene 3 tabs (Depositar / Retirar / **Stealth**) → cuenta "stealth + pool = un sistema de pagos privados", no dos demos sueltas.
- **`src/lib/stealth.ts`** (port 1:1 de `js/stealth.js` a TS) + **`StealthTab.tsx`** (flujo didáctico Bob genera meta-address → Alice genera stealth address + ephemeral + view tag → Bob deriva la privkey y se verifica en pantalla que controla los fondos; botones opcionales Registrar/Anunciar on-chain si hay addresses de Fase A). Cripto 100% client-side.
- **Cambio de dep (auditado):** subió `@noble/hashes` 1.3.2→2.2.0 y agregó `@noble/secp256k1@3.1.0` (mismas versiones que la lib de Fase A, para port idéntico). **Riesgo verificado por Fable:** re-corrí el smoke del pool → `PROOF OK` con raíz `19836...286003` IDÉNTICA → el bump NO afectó el Poseidon de circomlibjs. Descartado.
- **Verificación:** `npm run build` exit 0; `npm run smoke:stealth` → `STEALTH OK` (criterio duro: `addressFromPrivateKey(computeStealthKey(...)) === stealthAddress` + escaneo por view tag + rechazo de tercero). Cross-check determinista TS vs JS de Fase A → resultados idénticos.
- **Addresses Fase A por env:** `VITE_REGISTRY_ADDRESS`/`VITE_ANNOUNCER_ADDRESS` (placeholder fallback); sin ellas el tab funciona como demo cripto local completa.
- Commit refuerzo C: en esta corrida (dominio frontend/).

## 2026-07-09 — Refuerzo A+B (diseño Fable / ejecución Sonnet) — auditado

- **A — guard fee/relayer (hardening):** en `PrivacyPool.withdraw`, tras `fee <= denomination`, se agregó `require(relayer != address(0) || fee == 0, "fee > 0 requiere un relayer")`. Cierra el footgun documentado (fee atrapado si no hay relayer) → el invariante de balance vale universalmente. Test nuevo `test_Withdraw_RevertsIf_FeeWithoutRelayer`. **37/37 tests verdes** (era 36). Auditado por Fable: guard bien posicionado (antes de los checks de root/verify), ningún test previo roto.
- **SECURITY.md actualizado por Fable:** el footgun pasó de "Residual risks" a "Adversarial review / manejado".
- **B — scripts post-deploy one-shot:** `script/SeedDemo.s.sol` (siembra 3 depósitos de demo con notas deterministas PÚBLICAS (nullifier/secret = 1/11, 2/22, 3/33), commitment vía `hasher.poseidon`, y publica `getLastRoot` como association root → dApp demostrable en vivo SELF-SERVICE: un visitante retira con una nota de demo) + `script/PublishRoot.s.sol` (el owner del ASP publica la root vigente tras depósitos reales; modela el flujo operador del ASP). Ambos compilan.
- **Post-deploy:** las 3 notas de demo van al README para que cualquiera pruebe el retiro en vivo. Correr `SeedDemo` requiere 3×denominación (0.03 ETH) de faucet en el deployer.
- Commit refuerzo A+B: en esta corrida (solo dominio contratos/scripts/tests + SECURITY; frontend queda para el cierre del agente C).

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

[META-STATUS] 2026-07-10 | ESTADO=OPERATIVO | DESPLEGADO en Sepolia y repo PÚBLICO github.com/guillemustafa-ux/shieldedpay. 71 tests Foundry + 4 circuito verdes; dApp build verde. Fase A stealth + Fase B privacy pool ZK (6 contratos verificados + retiro ZK E2E real) + docs (THESIS/SECURITY/ARCHITECTURE/DECENTRALIZED-ASP) + **ASP DESCENTRALIZADO deployado on-chain** (ASPRegistry+PrivacyPoolMultiASP+FlaggedRegistry verificados, LOS TRES fraud proofs; SLASH tx 0x4d759e02 + retiro ZK multi-ASP tx 0xbb5bb8ff) + **dApp integrada al pool multi-ASP con selector de ASP** (lee el registry on-chain, slashed no elegible, pasa aspId; nota demo self-service sembrada). Falta SOLO redeploy de la dApp a Vercel (Guille).
