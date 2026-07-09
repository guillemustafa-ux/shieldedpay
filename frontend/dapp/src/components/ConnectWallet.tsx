interface Props {
  account: string | null;
  isConnecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
}

export function ConnectWallet({ account, isConnecting, onConnect, onDisconnect }: Props) {
  if (account) {
    return (
      <button
        onClick={onDisconnect}
        className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-slate-700 text-slate-300 text-sm hover:border-slate-500 hover:text-white transition-colors cursor-pointer"
      >
        <span className="size-2 rounded-full bg-emerald-400 shrink-0" />
        {account.slice(0, 6)}…{account.slice(-4)}
      </button>
    );
  }
  return (
    <button
      onClick={onConnect}
      disabled={isConnecting}
      className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-semibold transition-colors cursor-pointer"
    >
      {isConnecting ? "Conectando…" : "Conectar wallet"}
    </button>
  );
}
