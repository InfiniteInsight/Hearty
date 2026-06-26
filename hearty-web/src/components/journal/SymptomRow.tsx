import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../../lib/api";
import { SYMPTOM_TYPES, severityClass } from "../../lib/symptoms";
import type { SymptomResponse } from "@/types/api";

export default function SymptomRow({ symptom }: { symptom: SymptomResponse }) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [type, setType] = useState(symptom.symptom_type);
  const [severity, setSeverity] = useState(symptom.severity?.toString() ?? "");
  const [onset, setOnset] = useState(symptom.onset_minutes?.toString() ?? "");

  function invalidate() {
    for (const k of [["meals"], ["summary"], ["trends"]]) qc.invalidateQueries({ queryKey: k });
  }
  async function save() {
    if (busy) return;
    setBusy(true); setErr(null);
    try {
      await api.patchSymptom(symptom.id, {
        symptom_type: type,
        severity: severity === "" ? undefined : Number(severity),
        onset_minutes: onset === "" ? undefined : Number(onset),
      });
      invalidate();
      setEditing(false);
    } catch { setErr("Couldn't save."); } finally { setBusy(false); }
  }
  async function remove() {
    if (busy) return;
    setBusy(true); setErr(null);
    try { await api.deleteSymptom(symptom.id); invalidate(); }
    catch { setErr("Couldn't delete."); setBusy(false); }
  }

  function reset() {
    setEditing(false);
    setType(symptom.symptom_type);
    setSeverity(symptom.severity?.toString() ?? "");
    setOnset(symptom.onset_minutes?.toString() ?? "");
  }

  return (
    <div className="flex flex-col gap-1 py-1.5">
      {err && <p className="text-xs text-accent-red">{err}</p>}
      {!editing ? (
        <div className="flex items-center justify-between gap-3">
          <span className={`rounded-full px-2 py-0.5 text-xs ${severityClass(symptom.severity)}`}>
            {symptom.symptom_type}{symptom.severity != null ? ` ${symptom.severity}` : ""}
          </span>
          <div className="flex gap-2">
            <button aria-label={`Edit ${symptom.symptom_type}`} onClick={() => setEditing(true)}
              className="rounded-lg border border-surface-border px-2 py-1 text-xs">Edit</button>
            {!confirmDelete ? (
              <button aria-label={`Delete ${symptom.symptom_type}`} onClick={() => setConfirmDelete(true)}
                className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Delete</button>
            ) : (
              <>
                <button aria-label={`Confirm delete ${symptom.symptom_type}`} onClick={remove} disabled={busy}
                  className="rounded-lg bg-accent-red px-2 py-1 text-xs text-black disabled:opacity-40">Confirm delete</button>
                <button onClick={() => setConfirmDelete(false)}
                  className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
              </>
            )}
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Symptom type
            <select aria-label="Symptom type" value={type} onChange={(e) => setType(e.target.value)}
              className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
              {SYMPTOM_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Severity (1–10)
            <input aria-label="Severity" type="number" min={1} max={10} value={severity}
              onChange={(e) => setSeverity(e.target.value)}
              className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Onset (minutes)
            <input aria-label="Onset minutes" type="number" min={0} value={onset}
              onChange={(e) => setOnset(e.target.value)}
              className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <div className="flex gap-2">
            <button onClick={save} disabled={busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black disabled:opacity-40">Save</button>
            <button onClick={reset} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}
