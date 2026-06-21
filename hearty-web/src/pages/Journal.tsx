import { useJournalFilters } from "../hooks/useJournalFilters";
import { useJournalMeals, JOURNAL_PAGE_SIZE } from "../hooks/useJournalMeals";
import MealCard from "../components/journal/MealCard";

const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink", "supplement", "other"];
const SYMPTOM_TYPES = [
  "acid_reflux", "bloating", "gas", "nausea", "urgency", "loose_stool", "constipation",
  "stomach_pain", "cramping", "fatigue", "brain_fog", "headache", "skin_reaction",
  "heart_palpitations", "other",
];

export default function Journal() {
  const { filters, setFilters } = useJournalFilters();
  const meals = useJournalMeals(filters);
  const total = meals.data?.total ?? 0;
  const lastPage = Math.max(0, Math.ceil(total / JOURNAL_PAGE_SIZE) - 1);

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6 md:flex-row">
      {/* Filter panel */}
      <aside className="flex shrink-0 flex-col gap-3 md:w-60">
        <h1 className="font-display text-3xl">Journal</h1>
        <input
          defaultValue={filters.keyword ?? ""}
          placeholder="Search descriptions…"
          onKeyDown={(e) => { if (e.key === "Enter") setFilters({ keyword: (e.target as HTMLInputElement).value }); }}
          className="rounded-lg border border-surface-border bg-transparent px-3 py-2 text-sm"
        />
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          From
          <input type="date" value={filters.start_date ?? ""} onChange={(e) => setFilters({ start_date: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          To
          <input type="date" value={filters.end_date ?? ""} onChange={(e) => setFilters({ end_date: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          Meal type
          <select value={filters.meal_type ?? ""} onChange={(e) => setFilters({ meal_type: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
            <option value="">All</option>
            {MEAL_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          Symptom type
          <select value={filters.symptom_type ?? ""} onChange={(e) => setFilters({ symptom_type: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
            <option value="">All</option>
            {SYMPTOM_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
      </aside>

      {/* Entry list */}
      <section className="flex-1">
        {meals.isPending && <p className="text-text-faint">Loading…</p>}
        {meals.isError && <p className="text-sm text-accent-red">Couldn't load entries.</p>}
        {meals.isSuccess && total === 0 && <p className="text-text-faint">No entries match these filters.</p>}
        {meals.isSuccess && total > 0 && (
          <>
            <ul className="flex flex-col gap-2">
              {meals.data.meals.map((m) => (
                <MealCard key={m.id} meal={m} symptomTypeFilter={filters.symptom_type} />
              ))}
            </ul>
            <div className="mt-4 flex items-center justify-between font-mono-data text-xs text-text-faint">
              <button disabled={filters.page <= 0} onClick={() => setFilters({ page: filters.page - 1 })} className="rounded-lg border border-surface-border px-3 py-1 disabled:opacity-40">Prev</button>
              <span>Page {filters.page + 1} of {lastPage + 1} · {total} entries</span>
              <button disabled={filters.page >= lastPage} onClick={() => setFilters({ page: filters.page + 1 })} className="rounded-lg border border-surface-border px-3 py-1 disabled:opacity-40">Next</button>
            </div>
          </>
        )}
      </section>
    </div>
  );
}
