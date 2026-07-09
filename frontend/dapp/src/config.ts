// Configuración de red y contratos de ShieldedPay.
//
// Las direcciones se leen de variables de entorno (VITE_POOL_ADDRESS /
// VITE_ASP_ADDRESS) para que se completen DESPUÉS del deploy sin tocar código.
// Si no están seteadas, caen a un placeholder 0x000…000 y la UI muestra un
// banner pidiendo configurarlas. En Vercel se cargan como Environment
// Variables del proyecto; en local, en un archivo .env.local (no versionado).

export const SEPOLIA_CHAIN_ID = 11155111;
export const SEPOLIA_HEX_ID = "0xaa36a7";
export const EXPLORER = "https://sepolia.etherscan.io";

const PLACEHOLDER = "0x0000000000000000000000000000000000000000";

export const POOL_ADDRESS = (import.meta.env.VITE_POOL_ADDRESS ?? PLACEHOLDER).trim();
export const ASP_ADDRESS = (import.meta.env.VITE_ASP_ADDRESS ?? PLACEHOLDER).trim();

export function addressesConfigured(): boolean {
  return POOL_ADDRESS !== PLACEHOLDER && ASP_ADDRESS !== PLACEHOLDER;
}

// ABI mínimo del PrivacyPool (formato human-readable de ethers v6).
// Extraído de out/PrivacyPool.sol/PrivacyPool.json (sólo lo que usa la dApp).
export const POOL_ABI = [
  "function denomination() view returns (uint256)",
  "function isKnownRoot(uint256 root) view returns (bool)",
  "function commitments(uint256) view returns (bool)",
  "function nullifierHashes(uint256) view returns (bool)",
  "function deposit(uint256 commitment) payable",
  "function withdraw(uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256 root, uint256 associationRoot, uint256 nullifierHash, address recipient, address relayer, uint256 fee)",
  "event Deposit(uint256 indexed commitment, uint32 leafIndex, uint256 timestamp)",
  "event Withdrawal(address indexed to, uint256 indexed nullifierHash, address indexed relayer, uint256 fee)",
];

// ABI mínimo del ASP. Extraído de out/ASP.sol/ASP.json.
export const ASP_ABI = [
  "function latestAssociationRoot() view returns (uint256)",
  "function isKnownAssociationRoot(uint256 root) view returns (bool)",
  "event AssociationRootPublished(uint256 indexed root, uint256 timestamp)",
];

// Rutas de los artefactos ZK servidos como assets estáticos (public/zk/).
export const ZK_WASM_URL = "/zk/withdraw.wasm";
export const ZK_ZKEY_URL = "/zk/withdraw_final.zkey";
