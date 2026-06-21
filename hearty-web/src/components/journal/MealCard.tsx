import { useState } from "react";
import type { MealWithSymptoms } from "@/types/api";

function fmt(iso: string) {
  return new Date(iso).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function severityClass(sev?: number) {
  if (sev == null) return "bg-surface text-text-muted";
  if (sev <= 3) return "bg-brand/15 text-brand";
  if (sev <= 6) return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red";
}

export default function MealCard({
  meal,
  symptomTypeFilter,
}: {
  meal: MealWithSymptoms;
  symptomTypeFilter?: string;
}) {
  const [open, setOpen] = useState(false);
  const [showRaw, setShowRaw] = useState(false);
  const symptoms = symptomTypeFilter
    ? meal.symptoms.filter((s) => s.symptom_type === symptomTypeFilter)
    : meal.symptoms;

  return (
    <li className="rounded-xl border border-surface-border bg-surface">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center gap-3 px-4 py-3 text-left"
      >
        <span className="font-mono-data text-xs text-text-faint">{fmt(meal.logged_at)}</span>
        <span className="flex-1">{meal.description}</span>
        {meal.meal_type && <span className="font-mono-data text-xs text-text-faint">{meal.meal_type}</span>}
        <span className="text-text-faint">{open ? "▲" : "▼"}</span>
      </button>

      {((meal.foods?.length ?? 0) > 0 || symptoms.length > 0) && (
        <div className="flex flex-wrap gap-1 px-4 pb-3">
          {(meal.foods ?? []).map((f, i) => (
            <span key={`f${i}`} className="rounded-full bg-warn/15 px-2 py-0.5 text-xs text-warn">
              {f.name}
            </span>
          ))}
          {symptoms.map((s) => (
            <span key={s.id} className={`rounded-full px-2 py-0.5 text-xs ${severityClass(s.severity)}`}>
              {s.symptom_type}{s.severity != null ? ` ${s.severity}` : ""}
            </span>
          ))}
        </div>
      )}

      {open && (
        <div className="border-t border-surface-border px-4 py-3 text-sm">
          {meal.notes && <p className="text-text-muted">{meal.notes}</p>}
          <button
            onClick={() => setShowRaw((v) => !v)}
            className="mt-2 font-mono-data text-xs text-text-faint underline"
          >
            {showRaw ? "Hide raw data" : "Show raw data"}
          </button>
          {showRaw && (
            <pre className="mt-2 overflow-x-auto rounded-lg bg-black/30 p-2 font-mono-data text-xs text-text-muted">
              {JSON.stringify(meal, null, 2)}
            </pre>
          )}
        </div>
      )}
    </li>
  );
}
