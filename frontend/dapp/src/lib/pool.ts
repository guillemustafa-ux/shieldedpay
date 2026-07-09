// Interacción on-chain con el PrivacyPool y el ASP.

import { ethers } from "ethers";
import { POOL_ADDRESS, POOL_ABI, ASP_ADDRESS, ASP_ABI } from "../config";

export function getPool(runner: ethers.ContractRunner): ethers.Contract {
  return new ethers.Contract(POOL_ADDRESS, POOL_ABI, runner);
}

export function getASP(runner: ethers.ContractRunner): ethers.Contract {
  return new ethers.Contract(ASP_ADDRESS, ASP_ABI, runner);
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
