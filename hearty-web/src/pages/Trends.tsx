import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { useTrends } from "../hooks/useTrends";
import { useAnalyzeStatus, useAnalyze, useSignalVerdict } from "../hooks/useTrendsActions";
import { useUiStore, type TrendsPeriod } from "../lib/store";
import TrendsHero from "../components/signals/TrendsHero";
import SignalCard from "../components/signals/SignalCard";
import SymptomFrequencyChart from "../components/charts/SymptomFrequencyChart";
import MealTypeMixChart from "../components/charts/MealTypeMixChart";
import { symptomFrequency, mealTypeMix } from "../lib/charts";
import type { VerdictType } from "@/types/api";

const PERIODS: TrendsPeriod[] = ["7d", "30d", "90d"];
const DAYS: Record<TrendsPeriod, number> = { "7d": 7, "30d": 30, "90d": 90 };
const MEAL_CHART_CAP = 200;

function startDateFor(period: TrendsPeriod): string {
  const d = new Date();
  d.setDate(d.getDate() - DAYS[period]);
  return d.toISOString();
}

export default function Trends() {
  const trends = useTrends();
  const status = useAnalyzeStatus();
  const analyze = useAnalyze();
  const verdict = useSignalVerdict();
  const period = useUiStore((s) => s.trendsPeriod);
  const setPeriod = useUiStore((s) => s.setTrendsPeriod);
  const start = startDateFor(period);

  const symptoms = useQuery({
    queryKey: ["symptoms", { period }],
    queryFn: () => api.getSymptoms({ start_date: start, limit: 1000 }),
  });
  const chartMeals = useQuery({
    queryKey: ["meals", { period, chart: true }],
    queryFn: () => api.getMeals({ start_date: start, limit: MEAL_CHART_CAP }),
  });

  const analyzedAt = trends.data?.analyzed_at
    ? new Date(trends.data.analyzed_at).toLocaleDateString()
    : "never";

  function onVerdict(category: string, outcome_type: "symptom" | "wellbeing", outcome_name: string, v: VerdictType) {
    verdict.mutate({ category, outcome_type, outcome_name, verdict: v });
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-3xl">Trends</h1>
          <div className="font-mono-data text-xs text-text-faint">
            analysed {analyzedAt} · {trends.data?.total_meals_analyzed ?? 0} meals · {trends.data?.total_symptoms_analyzed ?? 0} symptoms
          </div>
        </div>
        <button
          onClick={() => analyze.mutate()}
          disabled={analyze.isPending}
          className="rounded-full bg-brand px-4 py-2 text-sm text-black disabled:opacity-50"
        >
          {analyze.isPending ? "Analysing…" : status.data?.has_new_data ? "Analyse (new data)" : "Analyse"}
        </button>
      </div>

      {/* Period selector (drives the charts) */}
      <div className="flex gap-1 font-mono-data text-xs">
        {PERIODS.map((p) => (
          <button
            key={p}
            onClick={() => setPeriod(p)}
            className={`rounded-lg px-3 py-1 ${p === period ? "bg-surface text-text" : "text-text-muted hover:text-text"}`}
          >
            {p}
          </button>
        ))}
      </div>

      {trends.isPending && <p className="text-text-faint">Loading signals…</p>}
      {trends.isError && <p className="text-sm text-accent-red">Couldn't load trends.</p>}
      {trends.isSuccess && (
        <>
          <TrendsHero data={trends.data} />

          <section className="flex flex-col gap-3">
            <h2 className="text-sm text-text-muted">Food signals</h2>
            {trends.data.signals.length === 0 ? (
              <p className="text-text-faint">No signals yet — keep logging and check back.</p>
            ) : (
              trends.data.signals.map((s) => {
                const ch = s.channels[0];
                return (
                  <SignalCard
                    key={s.category}
                    signal={s}
                    onVerdict={ch ? (v) => onVerdict(s.category, ch.outcome_type, ch.outcome_name, v) : undefined}
                  />
                );
              })
            )}
          </section>

          <section className="grid gap-4 md:grid-cols-2">
            <div className="rounded-2xl border border-surface-border bg-surface p-4">
              <h3 className="mb-2 text-sm text-text-muted">Symptom frequency · {period}</h3>
              {symptoms.isError
                ? <p className="text-sm text-accent-red">Couldn't load chart.</p>
                : symptoms.isSuccess
                  ? <SymptomFrequencyChart data={symptomFrequency(symptoms.data)} />
                  : <p className="text-text-faint text-sm">Loading…</p>}
            </div>
            <div className="rounded-2xl border border-surface-border bg-surface p-4">
              <h3 className="mb-2 text-sm text-text-muted">Meal-type mix · {period}</h3>
              {chartMeals.isError
                ? <p className="text-sm text-accent-red">Couldn't load chart.</p>
                : chartMeals.isSuccess
                  ? <>
                      <MealTypeMixChart data={mealTypeMix(chartMeals.data.meals)} />
                      {chartMeals.data.total > MEAL_CHART_CAP && (
                        <p className="mt-1 font-mono-data text-xs text-text-faint">showing first {MEAL_CHART_CAP} of {chartMeals.data.total} meals</p>
                      )}
                    </>
                  : <p className="text-text-faint text-sm">Loading…</p>}
            </div>
          </section>
        </>
      )}
    </div>
  );
}
