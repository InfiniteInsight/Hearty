import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import { useTodayMeals } from "../hooks/useMeals";
import { useTodaySymptoms } from "../hooks/useSymptoms";
import { useWeekSummary } from "../hooks/useSummary";
import { useTrends } from "../hooks/useTrends";
import StrongestSignalHero from "../components/signals/StrongestSignalHero";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

function timeOf(iso: string) { return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }); }

export default function Dashboard() {
  const qc = useQueryClient();
  const meals = useTodayMeals();
  const symptoms = useTodaySymptoms();
  const summary = useWeekSummary();
  const trends = useTrends();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [logError, setLogError] = useState<string | null>(null);

  // Fix 3: carry id through rows; ISO 8601 UTC strings: lexical order === chronological order
  const rows = [
    ...(meals.data?.meals ?? []).map((m) => ({ kind: "meal" as const, id: m.id, at: m.logged_at, label: m.description })),
    ...(symptoms.data ?? []).map((s) => ({ kind: "symptom" as const, id: s.id, at: s.logged_at, label: s.symptom_type })),
  ].sort((a, b) => a.at.localeCompare(b.at));

  // Fix 2: distinguish loading / error / empty
  const isLoading = meals.isPending || symptoms.isPending;
  const isError = meals.isError || symptoms.isError;

  // Fix 1: guard Enter double-submit + surface failures
  async function submit() {
    if (!text.trim() || busy) return;
    setBusy(true);
    setLogError(null);
    try {
      await api.createMeal({ description: text.trim(), input_method: "text" });
      setText("");
      qc.invalidateQueries({ queryKey: ["meals"] });
      qc.invalidateQueries({ queryKey: ["summary"] });
    } catch {
      setLogError("Couldn't save — tap Log to try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="font-display text-3xl">Today</h1>
      <div className="flex gap-2">
        <Input value={text} onChange={(e) => setText(e.target.value)} placeholder="Log a meal…"
          onKeyDown={(e) => { if (e.key === "Enter") submit(); }} />
        <Button onClick={submit} disabled={busy} className="bg-brand text-black">Log</Button>
      </div>
      {logError && <p className="text-sm text-accent-red">{logError}</p>}
      {summary.data && (
        <div className="rounded-2xl border border-surface-border bg-surface p-4">
          <div className="font-mono-data text-xs text-text-faint">THIS WEEK · {summary.data.meals_logged} meals</div>
          <p className="mt-1 text-text-muted">{summary.data.summary_text}</p>
        </div>
      )}
      <StrongestSignalHero data={trends.data} />
      <section>
        <h2 className="mb-2 text-sm text-text-muted">Today's timeline</h2>
        {isLoading && <p className="text-text-faint">Loading…</p>}
        {isError && <p className="text-sm text-accent-red">Couldn't load today's data.</p>}
        {!isLoading && !isError && rows.length === 0 && (
          <p className="text-text-faint">Nothing logged yet today.</p>
        )}
        {!isLoading && !isError && rows.length > 0 && (
          <ul className="flex flex-col gap-2">
            {rows.map((r) => (
              <li key={`${r.kind}-${r.id}`} className="flex items-center gap-3 rounded-xl border border-surface-border bg-surface px-4 py-2">
                <span className="font-mono-data text-xs text-text-faint">{timeOf(r.at)}</span>
                <span className={`h-2 w-2 rounded-full ${r.kind === "meal" ? "bg-brand" : "bg-accent-red"}`} />
                <span>{r.label}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
