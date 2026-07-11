// Interacción on-chain con el PrivacyPoolMultiASP y el ASPRegistry.

import { ethers } from "ethers";
import {
  POOL_ADDRESS,
  POOL_ABI,
  POOL_DEPLOY_BLOCK,
  ASP_REGISTRY_ADDRESS,
  ASP_REGISTRY_ABI,
} from "../config";

export function getPool(runner: ethers.ContractRunner): ethers.Contract {
  return new ethers.Contract(POOL_ADDRESS, POOL_ABI, runner);
}

export function getRegistry(runner: ethers.ContractRunner): ethers.Contract {
  return new ethers.Contract(ASP_REGISTRY_ADDRESS, ASP_REGISTRY_ABI, runner);
}

// Un ASP del registry, tal como lo muestra el selector de la dApp.
export interface AspInfo {
  id: number;
  owner: string;
  stake: bigint;
  slashed: boolean;
  active: boolean;
  latestRoot: bigint;
}

// Enumera los ASPs registrados (ids 1..nextAspId-1) con su estado. Así el
// usuario ve la lista real del registry on-chain — incluidos los SLASHED, que
// no se pueden elegir — sin que la dApp guarde estado propio.
export async function fetchAsps(provider: ethers.Provider): Promise<AspInfo[]> {
  const registry = getRegistry(provider);
  const next = Number(await registry.nextAspId());

  const asps: AspInfo[] = [];
  for (let id = 1; id < next; id++) {
    const info = await registry.asps(id);
    const active = await registry.isActive(id);
    asps.push({
      id,
      owner: String(info.owner),
      stake: BigInt(info.stake),
      slashed: Boolean(info.slashed),
      active,
      latestRoot: BigInt(info.latestRoot),
    });
  }
  return asps;
}

export interface DepositRecord {
  commitment: bigint;
  leafIndex: number;
}

// Lee TODOS los eventos Deposit del pool y devuelve los commitments ORDENADOS
// por leafIndex (orden de inserción en el árbol). Así la dApp reconstruye el
// árbol de estado idéntico al on-chain sin guardar estado propio.
//
// Escanea desde el bloque de deploy (no desde 0) y PAGINA en tramos ≤ CHUNK
// bloques: muchos RPCs (el default de varias wallets incluido) limitan
// eth_getLogs a ~10k bloques por consulta y rechazan un rango 0→latest.
export async function fetchDeposits(
  provider: ethers.Provider,
): Promise<DepositRecord[]> {
  const pool = getPool(provider);
  const filter = pool.filters.Deposit();
  const latest = await provider.getBlockNumber();
  const CHUNK = 9000; // margen bajo el límite típico de 10k.

  const records: DepositRecord[] = [];
  for (let from = POOL_DEPLOY_BLOCK; from <= latest; from += CHUNK) {
    const to = Math.min(from + CHUNK - 1, latest);
    const logs = await pool.queryFilter(filter, from, to);
    for (const log of logs) {
      const parsed = pool.interface.parseLog({
        topics: [...log.topics],
        data: log.data,
      });
      records.push({
        commitment: BigInt(parsed!.args[0]),
        leafIndex: Number(parsed!.args[1]),
      });
    }
  }

  records.sort((a, b) => a.leafIndex - b.leafIndex);
  return records;
}

export async function getDenomination(provider: ethers.Provider): Promise<bigint> {
  const pool = getPool(provider);
  return BigInt(await pool.denomination());
}
