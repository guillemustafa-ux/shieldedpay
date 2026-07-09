/// <reference types="vite/client" />

// circomlibjs no publica tipos. La usamos sólo vía buildPoseidon (ver
// merkleTree.ts), con el resultado tipado como any localmente.
declare module "circomlibjs";

interface Window {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ethereum?: any;
  // snarkjs se carga como script global desde public/snarkjs.min.js.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  snarkjs?: any;
}

interface ImportMetaEnv {
  readonly VITE_POOL_ADDRESS?: string;
  readonly VITE_ASP_ADDRESS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
