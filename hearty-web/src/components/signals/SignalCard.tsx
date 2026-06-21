import type { FoodSignal, VerdictType } from "@/types/api";

// eslint-disable-next-line react-refresh/only-export-components
export function dominantChannel(s: FoodSignal) {
  return s.channels.slice().sort((a, b) => (b.relative_risk ?? 0) - (a.relative_risk ?? 0))[0];
}

export default function SignalCard({
  signal,
  onVerdict,
}: {
  signal: FoodSignal;
  onVerdict?: (v: VerdictType) => void;
}) {
  const ch = dominantChannel(signal);
  const label = signal.category_label ?? signal.category;
  const harmful = ch?.direction === "harmful";
  const rrColor = harmful ? "text-accent-red" : "text-good";
  const barColor = harmful ? "bg-accent-red" : "bg-good";
  const pct = Math.round(Math.min(1, Math.max(0, signal.unified_score)) * 100);

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-lg">{label}</div>
          {ch && (
            <div className="text-sm text-text-muted">
              → {ch.outcome_name}
              {ch.peak_window_minutes ? ` · peaks ~${ch.peak_window_minutes}min` : ""}
            </div>
          )}
        </div>
        {ch?.relative_risk != null && (
          <div className={`font-mono-data text-lg ${rrColor}`}>{ch.relative_risk.toFixed(1)}×</div>
        )}
      </div>

      <div className="mt-3 h-2 w-full rounded-full bg-white/5">
        <div className={`h-2 rounded-full ${barColor}`} style={{ width: `${pct}%` }} />
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-2 font-mono-data text-xs text-text-faint">
        {ch && <span>based on {ch.evidence_count} logs</span>}
        {signal.convergent && <span className="rounded bg-accent-violet/20 px-1.5 py-0.5 text-accent-violet">CONVERGENT</span>}
        {signal.is_new && <span className="rounded bg-brand/20 px-1.5 py-0.5 text-brand">NEW</span>}
        {signal.recurring && <span className="rounded bg-white/10 px-1.5 py-0.5">RECURRING</span>}
      </div>

      {onVerdict && (
        <div className="mt-3 flex gap-2">
          <button onClick={() => onVerdict("confirmed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Confirm</button>
          <button onClick={() => onVerdict("disputed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Dispute</button>
          <button onClick={() => onVerdict("snoozed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Snooze</button>
        </div>
      )}
    </div>
  );
}
