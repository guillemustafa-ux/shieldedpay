# Deploy runbook (Sepolia)

Pasos para poner ShieldedPay en vivo en Sepolia + Vercel. Todo el código ya está
validado localmente (37 tests Foundry + 4 de circuito verdes, scripts de deploy
probados en simulación). Esto es solo la ejecución externa.

> Proyecto educativo / testnet. Usá **siempre una wallet descartable** con ETH de
> faucet, nunca una con fondos reales.

## 1. Prerrequisitos

Copiá `.env.example` a `.env` y completá:

```bash
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/TU_API_KEY   # Alchemy o Infura (gratis)
ETHERSCAN_API_KEY=...                                             # etherscan.io/myapikey (una key, API V2)
PRIVATE_KEY=...                                                   # wallet de prueba descartable
```

- **RPC:** cuenta gratis en [alchemy.com](https://alchemy.com) o [infura.io](https://infura.io) → app en red Sepolia → copiar la URL.
- **Etherscan key:** [etherscan.io/myapikey](https://etherscan.io/myapikey) (con API V2 la misma key verifica en Sepolia).
- **Wallet + fondos:** creá una wallet nueva (MetaMask), y fondeala con **~0.08 ETH de Sepolia** de un faucet (Google Cloud Web3 faucet, Alchemy faucet, etc.). Necesitás margen para: deploy Fase A, deploy Fase B (incluye el hasher Poseidon, que es caro), y los 3 depósitos de demo del seed (3 × 0.01 ETH).

Todos los comandos se corren desde **Git Bash** con Foundry en el PATH:

```bash
cd /c/Users/Cript/shieldedpay
export PATH="$HOME/.foundry/bin:$PATH"
```

## 2. Fase A — Stealth addresses

```bash
forge script script/DeployStealth.s.sol:DeployStealth --rpc-url sepolia --broadcast --verify -vvvv
```

Anotá las addresses que imprime: `ERC6538Registry` y `ERC5564Announcer`.

## 3. Fase B — Privacy Pool

```bash
forge script script/DeployPool.s.sol:DeployPool --rpc-url sepolia --broadcast --verify -vvvv
```

Anotá: `PrivacyPool` y `ASP` (también imprime hasher y verifier). Denominación por
defecto 0.01 ETH (configurable con `POOL_DENOMINATION` en wei).

## 4. Sembrar la demo (deja la dApp demostrable self-service)

Con las addresses del paso 3 en el entorno:

```bash
POOL_ADDRESS=0x... ASP_ADDRESS=0x... forge script script/SeedDemo.s.sol:SeedDemo --rpc-url sepolia --broadcast -vvvv
```

Inserta 3 depósitos de demo (notas públicas `nullifier/secret` = `1/11`, `2/22`,
`3/33`) y publica la association root. Un visitante puede retirar cualquiera de
esas 3 notas desde la dApp. Copiá las 3 notas al README (tabla de deployments).

> Para depósitos reales de usuarios (no demo), el owner del ASP corre
> `script/PublishRoot.s.sol` para publicar la association root vigente tras los
> nuevos depósitos (modela el flujo del operador del ASP).

## 5. Completar addresses

- **README.md** → tabla "Deployments (Sepolia)": pegar las 4 addresses + links a Etherscan.
- **dApp** (Vercel Environment Variables, o `frontend/dapp/.env.local` en local):
  ```bash
  VITE_POOL_ADDRESS=0x...
  VITE_ASP_ADDRESS=0x...
  VITE_REGISTRY_ADDRESS=0x...     # opcional (habilita registrar/anunciar on-chain en el tab Stealth)
  VITE_ANNOUNCER_ADDRESS=0x...    # opcional
  ```

## 6. dApp a Vercel

```bash
cd frontend/dapp
# vercel  (o conectar el repo en vercel.com; framework: Vite, output: dist)
```

El `vercel.json` ya está. La proving key (`public/zk/withdraw_final.zkey`, 9.6 MB)
está versionada para que el proving en browser funcione sin CDN externo.

## 7. Verificación end-to-end (que quede probado en vivo)

- Contratos **verificados** visibles en Etherscan (los links van al README).
- En la dApp: **Depositar** con una wallet Sepolia → guardar la nota → **Retirar**
  generando la prueba en el browser → los fondos llegan al recipient.
- O más rápido: **Retirar** directamente con una de las 3 notas de demo del seed.
- Tab **Stealth**: generar meta-address → stealth address → derivar la privkey (corre local, sin gas).
