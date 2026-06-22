import type { SignalsResponse } from "@/types/api";
export default function StrongestSignalHero({ data }: { data?: SignalsResponse }) {
  const top = data?.signals?.slice().sort((a, b) => b.unified_score - a.unified_score)[0];
  if (!top) return null;
  const ch = top.channels[0];
  const label = top.category_label ?? top.category;
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="font-mono-data text-xs text-text-faint">⚡ STRONGEST SIGNAL</div>
      <div className="mt-1 text-lg">{label}{ch ? <> → <span className="text-text-muted">{ch.outcome_name}</span></> : null}</div>
    </div>
  );
}
