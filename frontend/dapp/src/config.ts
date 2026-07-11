// Configuración de red y contratos de ShieldedPay.
//
// Los defaults son las addresses del deploy verificado en Sepolia (2026-07-10,
// ver README "Deployments") — datos públicos, así la dApp buildea lista para
// Vercel sin configurar nada. Para apuntar a OTRO deploy se pisan con
// variables de entorno (VITE_POOL_ADDRESS / etc.): en Vercel como Environment
// Variables del proyecto; en local, en un archivo .env.local (no versionado).

export const SEPOLIA_CHAIN_ID = 11155111;
export const SEPOLIA_HEX_ID = "0xaa36a7";
export const EXPLORER = "https://sepolia.etherscan.io";

const PLACEHOLDER = "0x0000000000000000000000000000000000000000";

// Deploy Sepolia 2026-07-10 (verificados en Etherscan; ver README).
// La dApp apunta al pool DESCENTRALIZADO (multi-ASP): el retiro se valida
// contra el ASP que el usuario elige en un registry con staking + slashing,
// en vez de un ASP single-owner. Ver README "Decentralized ASP".
const DEFAULT_POOL = "0xa84dbB140CF7d3cD0710E941D86Fc1969A89EA46";
const DEFAULT_ASP_REGISTRY = "0x31e8819d87EFf6b851Fc904b148022dFC70f31D3";
const DEFAULT_REGISTRY = "0xde3D1ae16e62E3A4D81A35D78f68eC576fcFd28f";
const DEFAULT_ANNOUNCER = "0x6122b8b6caADa7Cc6255bf0D62BC67d399eecf8f";

export const POOL_ADDRESS = (import.meta.env.VITE_POOL_ADDRESS ?? DEFAULT_POOL).trim();
export const ASP_REGISTRY_ADDRESS = (
  import.meta.env.VITE_ASP_REGISTRY_ADDRESS ?? DEFAULT_ASP_REGISTRY
).trim();

// Contratos de la Fase A (stealth addresses). La demo criptográfica del tab
// Stealth corre 100% client-side; con las addresses se habilitan además los
// botones de registrar/anunciar on-chain.
export const REGISTRY_ADDRESS = (import.meta.env.VITE_REGISTRY_ADDRESS ?? DEFAULT_REGISTRY).trim();
export const ANNOUNCER_ADDRESS = (import.meta.env.VITE_ANNOUNCER_ADDRESS ?? DEFAULT_ANNOUNCER).trim();

export function addressesConfigured(): boolean {
  return POOL_ADDRESS !== PLACEHOLDER && ASP_REGISTRY_ADDRESS !== PLACEHOLDER;
}

export function registryConfigured(): boolean {
  return REGISTRY_ADDRESS !== PLACEHOLDER;
}

export function announcerConfigured(): boolean {
  return ANNOUNCER_ADDRESS !== PLACEHOLDER;
}

// ABI mínimo del PrivacyPoolMultiASP (formato human-readable de ethers v6).
// El withdraw toma un `aspId` extra: el ASP del registry contra el que se
// valida la associationRoot (selector on-chain, NO señal del circuito).
export const POOL_ABI = [
  "function denomination() view returns (uint256)",
  "function isKnownRoot(uint256 root) view returns (bool)",
  "function commitments(uint256) view returns (bool)",
  "function nullifierHashes(uint256) view returns (bool)",
  "function deposit(uint256 commitment) payable",
  "function withdraw(uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256 root, uint256 associationRoot, uint256 nullifierHash, address recipient, address relayer, uint256 fee, uint256 aspId)",
  "event Deposit(uint256 indexed commitment, uint32 leafIndex, uint256 timestamp)",
  "event Withdrawal(address indexed to, uint256 indexed nullifierHash, address indexed relayer, uint256 fee)",
];

// ABI mínimo del ASPRegistry (multi-ASP). Sólo lo que la dApp lee/consulta:
// enumerar ASPs registrados, su estado y su última root publicada.
export const ASP_REGISTRY_ABI = [
  "function nextAspId() view returns (uint256)",
  "function asps(uint256) view returns (address owner, bytes32 policyHash, string metadataURI, uint256 stake, bool slashed, uint256 latestRoot, bytes32 latestDataHash, uint32 currentRootIndex)",
  "function isActive(uint256 aspId) view returns (bool)",
  "function isKnownRoot(uint256 aspId, uint256 root) view returns (bool)",
  "event RootPublished(uint256 indexed aspId, uint256 indexed root, bytes32 dataHash)",
];

// ABI mínimo del ERC6538Registry (Fase A). Extraído de
// out/ERC6538Registry.sol/ERC6538Registry.json.
export const REGISTRY_ABI = [
  "function registerKeys(uint256 schemeId, bytes stealthMetaAddress)",
  "function stealthMetaAddressOf(address registrant, uint256 schemeId) view returns (bytes)",
  "event StealthMetaAddressSet(address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress)",
];

// ABI mínimo del ERC5564Announcer (Fase A). Extraído de
// out/ERC5564Announcer.sol/ERC5564Announcer.json.
export const ANNOUNCER_ABI = [
  "function announce(uint256 schemeId, address stealthAddress, bytes ephemeralPubKey, bytes metadata)",
  "event Announcement(uint256 indexed schemeId, address indexed stealthAddress, address indexed caller, bytes ephemeralPubKey, bytes metadata)",
];

// schemeId 1 = secp256k1 (el único que implementa la lib de stealth).
export const STEALTH_SCHEME_ID = 1;

// Rutas de los artefactos ZK servidos como assets estáticos (public/zk/).
export const ZK_WASM_URL = "/zk/withdraw.wasm";
export const ZK_ZKEY_URL = "/zk/withdraw_final.zkey";
