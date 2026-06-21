import { useState } from "react";
import { useActiveExperiments, useExperimentActions } from "../hooks/useExperiments";
import ExperimentCard from "../components/experiments/ExperimentCard";
import { ApiError } from "../lib/api";

export default function Experiments() {
  const list = useActiveExperiments();
  const a = useExperimentActions();
  const [err, setErr] = useState<string | null>(null);
  const busy = a.create.isPending || a.evaluate.isPending || a.abandon.isPending || a.restart.isPending || a.ackNudge.isPending;

  function run(p: Promise<unknown>) {
    setErr(null);
    p.catch((e) => {
      if (e instanceof ApiError && e.status === 409) setErr("That action is no longer available — refreshing.");
      else setErr("Something went wrong. Try again.");
    });
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="font-display text-3xl">Experiments</h1>
      {err && <p className="text-sm text-accent-red">{err}</p>}
      {list.isPending && <p className="text-text-faint">Loading…</p>}
      {list.isError && <p className="text-sm text-accent-red">Couldn't load experiments.</p>}
      {list.isSuccess && list.data.experiments.length === 0 && (
        <p className="text-text-faint">No experiments yet. Start one from a trend in the chat.</p>
      )}
      {list.isSuccess && list.data.experiments.length > 0 && (
        <div className="flex flex-col gap-3">
          {list.data.experiments.map((exp) => (
            <ExperimentCard
              key={exp.id}
              exp={exp}
              actions={{
                busy,
                onEvaluate: () => run(a.evaluate.mutateAsync(exp.id)),
                onAbandon: () => run(a.abandon.mutateAsync(exp.id)),
                onRestart: () => run(a.restart.mutateAsync(exp.id)),
                onAckNudge: () => run(a.ackNudge.mutateAsync(exp.id)),
              }}
            />
          ))}
        </div>
      )}
    </div>
  );
}
