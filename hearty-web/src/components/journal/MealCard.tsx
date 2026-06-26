import { useState } from "react";
import { Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../../lib/api";
import type { MealWithSymptoms } from "@/types/api";
import { severityClass } from "../../lib/symptoms";
import SymptomRow from "./SymptomRow";

function fmt(iso: string) {
  return new Date(iso).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
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
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [desc, setDesc] = useState(meal.description);
  const [foods, setFoods] = useState((meal.foods ?? []).map((f) => f.name).join(", "));
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  function invalidate() {
    for (const k of [["meals"], ["summary"], ["trends"]]) qc.invalidateQueries({ queryKey: k });
  }
  async function save() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await api.patchMeal(meal.id, {
        description: desc.trim(),
        foods: foods.split(",").map((s) => s.trim()).filter(Boolean),
      });
      invalidate();
      setEditing(false);
    } catch {
      setErr("Couldn't save changes.");
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await api.deleteMeal(meal.id);
      invalidate();
    } catch {
      setErr("Couldn't delete.");
      setBusy(false);
    }
  }

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
          <div className="mt-2 flex items-center gap-3">
            <button
              onClick={() => setShowRaw((v) => !v)}
              className="font-mono-data text-xs text-text-faint underline"
            >
              {showRaw ? "Hide raw data" : "Show raw data"}
            </button>
            <Link to="/trends" className="font-mono-data text-xs text-text-faint underline">View trends</Link>
          </div>
          {showRaw && (
            <pre className="mt-2 overflow-x-auto rounded-lg bg-black/30 p-2 font-mono-data text-xs text-text-muted">
              {/* eslint-disable-next-line @typescript-eslint/no-unused-vars */}
              {JSON.stringify({ ...meal, foods: meal.foods?.map(({ estimated_calories: _estimated_calories, ...f }) => f) }, null, 2)}
            </pre>
          )}
          {err && <p className="mt-2 text-xs text-accent-red">{err}</p>}
          {!editing ? (
            <div className="mt-3 flex gap-2">
              <button onClick={() => setEditing(true)} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Edit</button>
              {!confirmDelete ? (
                <button onClick={() => setConfirmDelete(true)} className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Delete</button>
              ) : (
                <>
                  <button onClick={remove} disabled={busy} className="rounded-lg bg-accent-red px-2 py-1 text-xs text-black">Confirm delete</button>
                  <button onClick={() => setConfirmDelete(false)} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
                </>
              )}
            </div>
          ) : (
            <div className="mt-3 flex flex-col gap-2">
              <label className="flex flex-col gap-1 text-xs text-text-muted">
                Description
                <input value={desc} onChange={(e) => setDesc(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </label>
              <label className="flex flex-col gap-1 text-xs text-text-muted">
                Foods (comma-separated)
                <input value={foods} onChange={(e) => setFoods(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </label>
              <div className="flex gap-2">
                <button onClick={save} disabled={busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black">Save</button>
                <button onClick={() => { setEditing(false); setDesc(meal.description); setFoods((meal.foods ?? []).map((f) => f.name).join(", ")); }} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
              </div>
            </div>
          )}
          {symptoms.length > 0 && (
            <div className="mt-3 border-t border-surface-border pt-3">
              <p className="mb-1 text-xs text-text-muted">Symptoms</p>
              {symptoms.map((s) => <SymptomRow key={s.id} symptom={s} />)}
            </div>
          )}
        </div>
      )}
    </li>
  );
}
