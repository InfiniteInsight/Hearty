import type { SignalsResponse } from "@/types/api";

export default function TrendsHero({ data }: { data?: SignalsResponse }) {
  const top = data?.signals?.slice().sort((a, b) => b.unified_score - a.unified_score)[0];
  if (!top) return null;
  const ch = top.channels[0];
  const label = top.category_label ?? top.category;

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-6"
      style={{ boxShadow: "0 0 40px var(--glow-emerald)" }}>
      <div className="font-mono-data text-xs text-text-faint">⚡ STRONGEST SIGNAL</div>
      <div className="mt-1 font-display text-2xl">{label}</div>
      {ch && <div className="text-text-muted">→ {ch.outcome_name}</div>}
      {ch && (
        <div className="mt-4 grid grid-cols-3 gap-3 font-mono-data text-sm">
          <div>
            <div className="text-text-faint text-xs">RELATIVE RISK</div>
            <div className="text-accent-red">{ch.relative_risk != null ? `${ch.relative_risk.toFixed(1)}×` : "—"}</div>
          </div>
          <div>
            <div className="text-text-faint text-xs">PEAK WINDOW</div>
            <div>{ch.peak_window_minutes != null ? `${ch.peak_window_minutes} min` : "—"}</div>
          </div>
          <div>
            <div className="text-text-faint text-xs">EVIDENCE</div>
            <div>{ch.evidence_count} logs</div>
          </div>
        </div>
      )}
    </div>
  );
}
