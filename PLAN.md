# ShieldedPay — Roadmap de build

Sistema de pagos privados: **Fase A stealth addresses** (ERC-5564/6538) + **Fase B Privacy Pool compliant** (ZK + association sets). Sin deadline fijo; se avanza por fases con criterios de aceptación verificables. Detalle de arquitectura y tesis en `CLAUDE.md` y `docs/THESIS.md`.

## D0 — Andamiaje ✅ (en curso)
Convenciones (foundry.toml, .gitignore, CI, .env.example, remappings), submódulos forge-std v1.16.1 + OZ v5.6.1, CLAUDE.md, PLAN.md, state/log.md, commit inicial.
- **Aceptación:** `forge build` exit 0; `git log` con commit inicial; submódulos presentes.

## D1 — Fase A: Stealth addresses
- `src/ERC6538Registry.sol` (registro de stealth meta-addresses) + `src/ERC5564Announcer.sol` (evento Announcement).
- Tests Foundry: registro, anuncio, derivación de privkey por el receptor. ~90%+ coverage, ≥1 invariant.
- Lib JS de derivación stealth (ECDH secp256k1) + demo end-to-end.
- Deploy + verify Sepolia (con OK de Guille).
- **Aceptación:** `forge test` verde; contratos verificados en Etherscan; demo muestra transferencia stealth punta a punta.

## D2 — Fase B parte 1: circuito + prueba local (mayor riesgo)
- Instalar Circom + snarkjs; bajar `.ptau` Hermez + verificar hash.
- `circuits/withdraw.circom`: commitment=Poseidon(nullifier,secret); membership proof (root estado); membership de asociación (associationRoot); nullifierHash; binding recipient/relayer/fee.
- Compilar, fase 2 setup, generar `src/verifiers/WithdrawVerifier.sol`.
- Tests de circuito: válidos OK, inválidos rechazados.
- **Aceptación:** `snarkjs groth16 fullprove` + `verify` = OK; casos inválidos rechazados.

## D3 — Fase B parte 2: contratos + retiro on-chain
- `src/PrivacyPool.sol` (Merkle de commitments + nullifiers gastados) + `src/ASP.sol` (raíz del set limpio) integrando el verifier.
- Tests: depósito, retiro con proof válida, rechazo de nullifier repetido, rechazo de proof inválida, exclusión ASP. Invariant + test de double-spend.
- Deploy + verify Sepolia.
- **Aceptación:** `forge test` verde; PrivacyPool + Verifier verificados; retiro on-chain con prueba real funciona.

## D4 — dApp con proving en browser
- `frontend/dapp` Vite+React+TS+Tailwind+ethers v6: depósito → nota → retiro con prueba generada client-side (snarkjs wasm).
- Deploy Vercel.
- **Aceptación:** dApp genera prueba en el browser y ejecuta retiro en Sepolia; screenshot.

## D5 — Documentación + posicionamiento
- README (patrón botpass/yield-vault) + diagrama + tabla de deployments verificados.
- `docs/THESIS.md` (comparativa Tornado/Railgun/Privacy Pools/Aztec + mapeo Kohaku/EIP-8182/PSE).
- SECURITY.md con Slither + disclaimers. Cierre auditoría Fable.
- **Aceptación:** README completo; THESIS.md; SECURITY.md con residual risks; todo commiteado.

## Post-ventana (con OK de Guille)
`git remote add` + push a `guillemustafa-ux/shieldedpay`; cross-link desde portfolio site; Loom.
