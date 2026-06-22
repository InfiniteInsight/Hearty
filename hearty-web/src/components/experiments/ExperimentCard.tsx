import type { ExperimentResponse, ExperimentResult } from "@/types/api";

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString();
}
function verdictClass(v: ExperimentResult["verdict"]) {
  if (v === "improved") return "text-good";
  if (v === "worse") return "text-accent-red";
  return "text-text-muted";
}

export interface ExperimentActions {
  onEvaluate: () => void;
  onAbandon: () => void;
  onRestart: () => void;
  onAckNudge: () => void;
  busy: boolean;
}

export default function ExperimentCard({
  exp,
  actions,
}: {
  exp: ExperimentResponse;
  actions: ExperimentActions;
}) {
  const label = exp.category_label ?? exp.category;
  const isActive = exp.status === "active";
  const pct = Math.round(Math.min(1, Math.max(0, exp.adherence ?? 0)) * 100);

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-lg">{label}</div>
          <div className="text-sm text-text-muted">
            {exp.direction} → {exp.outcome_name}
          </div>
        </div>
        <span className="font-mono-data text-xs text-text-faint uppercase">{exp.status}</span>
      </div>

      <div className="mt-2 font-mono-data text-xs text-text-faint">
        {fmtDate(exp.experiment_start)} – {fmtDate(exp.experiment_end)}
      </div>

      {isActive && (
        <div className="mt-3">
          <div className="flex justify-between font-mono-data text-xs text-text-faint">
            <span>adherence</span>
            <span>{pct}% · {exp.logged_days ?? 0} days logged</span>
          </div>
          <div className="mt-1 h-2 w-full rounded-full bg-white/5">
            <div className="h-2 rounded-full bg-brand" style={{ width: `${pct}%` }} />
          </div>
        </div>
      )}

      {isActive && exp.nudge_suggested && (
        <div className="mt-3 flex items-center justify-between rounded-lg border border-warn/40 bg-warn/10 px-3 py-2 text-sm text-warn">
          <span>Logging has dipped — keep it up to get a clear result.</span>
          <button onClick={actions.onAckNudge} disabled={actions.busy} className="rounded-lg border border-warn/40 px-2 py-1 text-xs">Got it</button>
        </div>
      )}

      {exp.result && (
        <div className="mt-3 rounded-lg border border-surface-border bg-black/20 p-3 text-sm">
          <div>
            Result: <span className={`font-mono-data ${verdictClass(exp.result.verdict)}`}>{exp.result.verdict}</span>
            {exp.result.reason ? <span className="text-text-faint"> ({exp.result.reason})</span> : null}
          </div>
          {exp.result.baseline_rate != null && exp.result.experiment_rate != null && (
            <div className="mt-1 font-mono-data text-xs text-text-faint">
              rate {exp.result.baseline_rate} → {exp.result.experiment_rate} · adherence {Math.round(exp.result.adherence * 100)}%
            </div>
          )}
        </div>
      )}

      <div className="mt-3 flex flex-wrap gap-2">
        {isActive ? (
          <>
            <button onClick={actions.onEvaluate} disabled={actions.busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black">Evaluate</button>
            <button onClick={actions.onAbandon} disabled={actions.busy} className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Abandon</button>
          </>
        ) : (
          <button onClick={actions.onRestart} disabled={actions.busy} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Restart</button>
        )}
      </div>
    </div>
  );
}
