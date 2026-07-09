import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { nodePolyfills } from 'vite-plugin-node-polyfills'

// Notas sobre ZK en el browser (ver también index.html y src/lib/zk.ts):
//
// 1) snarkjs asume globals de Node y no se empaqueta limpio con Vite. En vez de
//    pelear con el bundler, lo cargamos como SCRIPT GLOBAL desde public/
//    (window.snarkjs) — mismo approach que las dApps estilo Tornado. Por eso
//    snarkjs NO se importa como módulo ESM en el código de la app.
//
// 2) circomlibjs (Poseidon) SÍ se importa como módulo, pero internamente usa
//    builtins de Node (assert, buffer, events). Sin polyfills, Vite los
//    externaliza y quedan `undefined` en runtime → el proving rompe en el
//    browser. vite-plugin-node-polyfills los provee.
export default defineConfig({
  plugins: [
    nodePolyfills(),
    tailwindcss(),
    react(),
  ],
})
