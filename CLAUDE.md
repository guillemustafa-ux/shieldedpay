# ShieldedPay — CLAUDE.md

Contexto e instrucciones para cualquier sesión de Claude Code que trabaje este repo.
Sesión sin memoria: todo lo necesario para operar está acá.

## Misión

Sistema de **pagos privados on-chain** en dos capas, como pieza de portfolio Web3/privacy de Guille Mustafa:

1. **Fase A — Stealth addresses (ERC-5564 + ERC-6538):** capa de *recepción* privada. El pagador manda a una dirección nueva derivada; nadie más liga esos pagos al receptor.
2. **Fase B — Privacy Pool compliant (ZK + association sets):** capa que *rompe el link* depósito↔retiro, pero con **prueba de exclusión** contra un set de depósitos marcados (diseño Privacy Pools de Vitalik/Illum/Nadler/Schär 2023, lo que 0xbow shippeó en mainnet). No es un mixer plano.

## Tesis (por qué este proyecto, por qué ahora)

La privacidad on-chain es una de las narrativas cripto más financiadas hoy: Privacy Pools (0xbow) en mainnet desde mar-2025, integrado por la Ethereum Foundation en su wallet Kohaku y demostrado en Devconnect Buenos Aires; $3.5M seed de Coinbase Ventures (nov-2025); EIP-8182 (shielded pool a nivel protocolo) y la iniciativa PSE. Construir sobre **compliant privacy (association sets)** alinea el proyecto con quien contrata y financia, y lo diferencia de la masa de clones de Tornado. Detalle en `docs/THESIS.md`.

## Reglas duras

- **Proyecto educativo / portfolio. NO auditado. NO usar con fondos reales.** Este disclaimer va en README y SECURITY.md, y no se suaviza.
- **Nunca se declara "auditado", "seguro para fondos reales" ni se promete rentabilidad/anonimato perfecto.** Se documenta explícitamente qué privacidad da y qué NO da.
- **Secrets jamás al repo.** `.env` está en `.gitignore`. Solo `.env.example` con placeholders.
- **Trusted setup:** usar SIEMPRE un `.ptau` de una ceremony pública existente (Hermez / Perpetual Powers of Tau), descargado y verificado por hash. NUNCA improvisar un trusted setup propio para algo que se presente como real. Los `.ptau`/`.zkey` NO se versionan (ver `.gitignore`).
- **Push público (`git remote add` + push) es acción externa:** requiere OK explícito de Guille. Hasta entonces, git local sin remote.
- **Deploy a testnet (Sepolia) requiere OK de Guille** (usa gas de faucet y expone addresses).

## Estrategia de modelos (sandwich)

- **Fable diseña y audita:** arquitectura de contratos, diseño del circuito Circom, prompts de subagentes. En cierres revisa outputs; si algo sale mal, corrige el prompt/diseño, no el output a mano.
- **Sonnet ejecuta:** boilerplate Solidity, tests Foundry, loop de tooling ZK (instalar Circom, trusted setup, generar verifier), redacción de docs, dApp.
- **Prohibido** usar Fable para trabajo mecánico. El loop de prueba-error del tooling ZK es 100% Sonnet.

## Entorno (Windows 11 — restricciones duras)

- **Foundry** desde Git Bash: binarios en `~/.foundry/bin` (`~/.foundry/bin/forge.exe`, no está en PATH del sistema). Versión: forge 1.7.x.
- **PowerShell 5.1: NO usar `&&`** (usar `;` o comandos separados). `curl` y `grep` desde el tool **Bash** (en PowerShell `curl` es alias de Invoke-WebRequest y `grep` no existe).
- **El cwd del tool Bash se resetea entre llamadas.** Empezar cada comando con `cd /c/Users/Cript/shieldedpay`.
- Archivos: **UTF-8 sin BOM**.
- **Frontend: Vite + React (NO Next.js** — se cuelga determinísticamente en esta máquina).
- **Circom/snarkjs** vía npm (`circom` binario vía cargo/release; `snarkjs` vía npm). Node presente.

## Dependencias

- `lib/forge-std` @ v1.16.1 · `lib/openzeppelin-contracts` @ v5.6.1 (submódulos git, ver `.gitmodules` + `remappings.txt`).
- Circom lib de hashes: **circomlib** (Poseidon, Merkle) — se instala vía npm en `circuits/`.

## Mapa de archivos y ownership (un dueño por dominio)

| Dominio | Archivo(s) | Notas |
|---|---|---|
| Stealth (Fase A) | `src/ERC6538Registry.sol`, `src/ERC5564Announcer.sol` | Contratos solo registran/anuncian; la cripto ECDH es off-chain (JS). |
| Circuito ZK | `circuits/withdraw.circom` | El corazón. Diseño Fable. Verifier generado → `src/verifiers/WithdrawVerifier.sol` (NO editar a mano). |
| Pool (Fase B) | `src/PrivacyPool.sol`, `src/ASP.sol` | Merkle de commitments + nullifiers gastados; ASP publica la raíz del set limpio. |
| Merkle on-chain | `src/lib/` (helper de Merkle incremental) | Poseidon, altura fija, historial de roots. |
| Derivación stealth JS | `js/` o `frontend/dapp/src/lib/` | ECDH secp256k1, generación/derivación de stealth address. |
| dApp | `frontend/dapp/` | Vite+React+TS+Tailwind+ethers v6; proving snarkjs wasm client-side. |
| Estado del proyecto | `state/log.md` | Bitácora append-only de corridas y decisiones autónomas. |
| Docs | `README.md`, `docs/THESIS.md`, `SECURITY.md` | Posicionamiento + disclaimers. |

## Comandos de referencia (desde Git Bash)

```bash
cd /c/Users/Cript/shieldedpay
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test -vv                                   # unit + fuzz + invariant
forge coverage --report summary
forge snapshot --no-match-contract Invariant     # regenerar .gas-snapshot
# Circuito (Fase B):
cd circuits && npm run build                      # compila + genera verifier
# Deploy (requiere OK de Guille):
forge script script/DeployStealth.s.sol:DeployStealth --rpc-url sepolia --broadcast --verify -vvvv
```

## Estado actual

Ver `PLAN.md` (roadmap D0–D5) y `state/log.md` (bitácora).

## Reporte al meta-nivel
Al cerrar cada corrida o sesión de trabajo, agregar al final de `state/log.md` una línea:
`[META-STATUS] YYYY-MM-DD | ESTADO=OPERATIVO|EN_DESARROLLO|BLOQUEADO|PAUSADO | resumen de una línea`
La lee `C:\Users\Cript\init.sh` para generar la vista de conjunto `SISTEMA-STATUS.md` de todos los proyectos.
