// Interacción on-chain con el PrivacyPoolMultiASP y el ASPRegistry.

import { ethers } from "ethers";
import {
  POOL_ADDRESS,
  POOL_ABI,
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
export async function fetchDeposits(
  provider: ethers.Provider,
): Promise<DepositRecord[]> {
  const pool = getPool(provider);
  const filter = pool.filters.Deposit();
  const logs = await pool.queryFilter(filter, 0, "latest");

  const records: DepositRecord[] = logs.map((log) => {
    const parsed = pool.interface.parseLog({
      topics: [...log.topics],
      data: log.data,
    });
    return {
      commitment: BigInt(parsed!.args[0]),
      leafIndex: Number(parsed!.args[1]),
    };
  });

  records.sort((a, b) => a.leafIndex - b.leafIndex);
  return records;
}

export async function getDenomination(provider: ethers.Provider): Promise<bigint> {
  const pool = getPool(provider);
  return BigInt(await pool.denomination());
}
