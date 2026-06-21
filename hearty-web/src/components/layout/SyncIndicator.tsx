export type SyncStatus = "live" | "reconnecting" | "offline";
export default function SyncIndicator({ status }: { status: SyncStatus }) {
  const color = status === "live" ? "bg-brand" : status === "reconnecting" ? "bg-yellow-400 animate-pulse" : "bg-accent-red";
  const label = status === "live" ? "Live" : status === "reconnecting" ? "Reconnecting…" : "Offline";
  return <span className="flex items-center gap-2 text-xs text-text-muted"><span className={`h-2 w-2 rounded-full ${color}`} /> {label}</span>;
}
