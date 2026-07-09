# ShieldedPay — Bitácora (append-only)

Registro de corridas, decisiones autónomas y bloqueos. Lo más nuevo arriba.

---

## 2026-07-09 — D0: Andamiaje

- `git init` en `C:\Users\Cript\shieldedpay` (sin remote — push público requiere OK de Guille).
- Entorno confirmado: git 2.54.0, forge 1.7.1, curva de trabajo Sepolia.
- Convenciones calcadas de botpass/yield-vault: `foundry.toml` (solc 0.8.24, invariant runs=256/depth=50, rpc+etherscan Sepolia), `.gitignore` (+ reglas ZK: ignora `circuits/build/`, `*.ptau`, `*.zkey`, `*.r1cs`, `*.wtns`; versiona el verifier), `remappings.txt`, `.github/workflows/test.yml`, `.env.example` (adaptado: sin params BotPass, con `POOL_DENOMINATION` opcional).
- `CLAUDE.md` del proyecto escrito (misión, tesis, reglas duras, entorno, ownership).
- **Decisión autónoma:** `foundry.toml` solo declara Sepolia (no Base/Arbitrum como botpass) — el proyecto es standalone y no necesita multi-red. Reversible si se quiere multi-deploy después.
- Pendiente: instalar submódulos (forge-std v1.16.1 + OZ v5.6.1), `forge build` seco, commit inicial.
