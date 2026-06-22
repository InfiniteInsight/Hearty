import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { saveBlob } from "../lib/download";
import type { ExportDateRange } from "@/types/api";

export default function Reports() {
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [range, setRange] = useState<{ start_date: string; end_date: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const params: ExportDateRange = {};
  if (start) params.start_date = start;
  if (end) params.end_date = end;

  const preview = useQuery({
    queryKey: ["summary", { period: "custom", ...range }],
    queryFn: () => api.getSummary({ period: "custom", start_date: range!.start_date, end_date: range!.end_date }),
    enabled: range != null,
  });

  async function download(kind: "csv" | "json" | "pdf") {
    setBusy(kind);
    setErr(null);
    try {
      const dl = kind === "pdf" ? await api.exportPdf(params) : kind === "csv" ? await api.exportCsv(params) : await api.exportJson(params);
      saveBlob(dl.blob, dl.filename);
    } catch {
      setErr(`Couldn't export ${kind.toUpperCase()}. Try again.`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Reports</h1>

      <div className="rounded-2xl border border-surface-border bg-surface p-4">
        <div className="flex flex-wrap gap-3">
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            From
            <input type="date" value={start} onChange={(e) => setStart(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            To
            <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <button
            onClick={() => start && end && setRange({ start_date: start, end_date: end })}
            disabled={!start || !end}
            className="self-end rounded-lg border border-surface-border px-3 py-1 text-sm disabled:opacity-40"
          >
            Preview
          </button>
        </div>
        <p className="mt-2 font-mono-data text-xs text-text-faint">Leave dates empty to export your full history.</p>
      </div>

      {range && (
        <div className="rounded-2xl border border-surface-border bg-surface p-4">
          {preview.isPending && <p className="text-text-faint">Loading preview…</p>}
          {preview.isError && <p className="text-sm text-accent-red">Couldn't load the preview.</p>}
          {preview.isSuccess && (
            <>
              <div className="font-mono-data text-xs text-text-faint">{preview.data.meals_logged} meals logged</div>
              <p className="mt-1 text-text-muted">{preview.data.summary_text}</p>
            </>
          )}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <button onClick={() => download("csv")} disabled={busy != null} className="rounded-lg bg-brand px-3 py-2 text-sm text-black disabled:opacity-50">{busy === "csv" ? "Exporting…" : "Export CSV"}</button>
        <button onClick={() => download("json")} disabled={busy != null} className="rounded-lg border border-surface-border px-3 py-2 text-sm disabled:opacity-50">{busy === "json" ? "Exporting…" : "Export JSON"}</button>
        <button onClick={() => download("pdf")} disabled={busy != null} className="rounded-lg border border-surface-border px-3 py-2 text-sm disabled:opacity-50">{busy === "pdf" ? "Generating…" : "Export PDF"}</button>
      </div>
      {err && <p className="text-sm text-accent-red">{err}</p>}
    </div>
  );
}
