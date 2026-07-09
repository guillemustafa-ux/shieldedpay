import { useState, useCallback, useEffect } from "react";
import { ethers } from "ethers";
import { SEPOLIA_HEX_ID } from "../config";

export interface WalletState {
  account: string | null;
  chainId: number | null;
  signer: ethers.JsonRpcSigner | null;
  provider: ethers.BrowserProvider | null;
  isConnecting: boolean;
  error: string | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  switchToSepolia: () => Promise<void>;
}

export function useWallet(): WalletState {
  const [account, setAccount] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [signer, setSigner] = useState<ethers.JsonRpcSigner | null>(null);
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const connect = useCallback(async () => {
    if (!window.ethereum) {
      setError("No se detectó wallet. Instalá MetaMask.");
      return;
    }
    try {
      setIsConnecting(true);
      setError(null);
      const p = new ethers.BrowserProvider(window.ethereum);
      await p.send("eth_requestAccounts", []);
      const s = await p.getSigner();
      const addr = await s.getAddress();
      const network = await p.getNetwork();
      setProvider(p);
      setSigner(s);
      setAccount(addr);
      setChainId(Number(network.chainId));
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Error al conectar");
    } finally {
      setIsConnecting(false);
    }
  }, []);

  const disconnect = useCallback(() => {
    setAccount(null);
    setChainId(null);
    setSigner(null);
    setProvider(null);
    setError(null);
  }, []);

  const switchToSepolia = useCallback(async () => {
    if (!window.ethereum) return;
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: SEPOLIA_HEX_ID }],
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "No se pudo cambiar a Sepolia");
    }
  }, []);

  useEffect(() => {
    if (!window.ethereum) return;
    const reload = () => window.location.reload();
    window.ethereum.on("accountsChanged", reload);
    window.ethereum.on("chainChanged", reload);
    return () => {
      window.ethereum?.removeListener("accountsChanged", reload);
      window.ethereum?.removeListener("chainChanged", reload);
    };
  }, []);

  useEffect(() => {
    if (window.ethereum?.selectedAddress) {
      connect();
    }
  }, [connect]);

  return {
    account,
    chainId,
    signer,
    provider,
    isConnecting,
    error,
    connect,
    disconnect,
    switchToSepolia,
  };
}
