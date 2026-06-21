import { useState } from "react";
import { useConversation } from "../hooks/useConversation";
import { api, ApiError } from "../lib/api";
import type { VerdictType } from "@/types/api";

export default function Conversation() {
  const c = useConversation();
  const [draft, setDraft] = useState("");
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  async function submit() {
    const text = draft.trim();
    if (!text) return;
    setDraft("");
    await c.send(text);
  }

  async function verdict(v: VerdictType) {
    if (!c.proposedVerdict) return;
    const { category, outcome_type, outcome_name } = c.proposedVerdict;
    setActionMsg(null);
    try {
      await api.signalVerdict({ category, outcome_type, outcome_name, verdict: v });
      setActionMsg(`Marked as ${v}.`);
      c.clearProposals();
    } catch {
      setActionMsg("Couldn't save that.");
    }
  }

  async function startExperiment() {
    if (!c.proposedExperiment) return;
    const { category, outcome_type, outcome_name } = c.proposedExperiment;
    setActionMsg(null);
    try {
      await api.createExperiment({ category, outcome_type, outcome_name });
      setActionMsg("Experiment started — track it on the Experiments page.");
      c.clearProposals();
    } catch (e) {
      setActionMsg(e instanceof ApiError && e.status === 409 ? "An experiment for this is already running." : "Couldn't start the experiment.");
    }
  }

  return (
    <div className="mx-auto flex h-full max-w-2xl flex-col gap-4">
      <h1 className="font-display text-3xl">Chat about your trends</h1>

      <div className="flex flex-1 flex-col gap-3">
        {c.history.map((t, i) => (
          <div key={i} className={t.role === "user" ? "self-end max-w-[80%]" : "self-start max-w-[80%]"}>
            <div className={`rounded-2xl px-4 py-2 ${t.role === "user" ? "bg-brand text-black" : "bg-surface text-text"}`}>
              {t.content}
            </div>
          </div>
        ))}
        {c.isSending && <div className="self-start text-text-faint text-sm">Hearty is typing…</div>}
      </div>

      {c.proposedVerdict && (
        <div className="rounded-2xl border border-surface-border bg-surface p-3">
          <div className="text-sm text-text-muted">
            Confirm {c.proposedVerdict.category_label ?? c.proposedVerdict.category} → {c.proposedVerdict.outcome_name}?
          </div>
          <div className="mt-2 flex gap-2">
            <button onClick={() => verdict("confirmed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Confirm</button>
            <button onClick={() => verdict("disputed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Dispute</button>
            <button onClick={() => verdict("snoozed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Snooze</button>
          </div>
        </div>
      )}

      {c.proposedExperiment && (
        <div className="rounded-2xl border border-surface-border bg-surface p-3">
          <div className="text-sm text-text-muted">
            Start a 2-week experiment on {c.proposedExperiment.category_label ?? c.proposedExperiment.category}?
          </div>
          <button onClick={startExperiment} className="mt-2 rounded-lg bg-brand px-2 py-1 text-xs text-black">Start experiment</button>
        </div>
      )}

      {actionMsg && <p className="text-sm text-text-muted">{actionMsg}</p>}
      {c.error && <p className="text-sm text-accent-red">{c.error}</p>}
      {c.isClosing && <p className="text-sm text-text-faint">This conversation has wrapped up.</p>}

      <div className="flex gap-2">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") submit(); }}
          disabled={c.isSending || c.isClosing}
          placeholder="Message Hearty…"
          className="flex-1 rounded-lg border border-surface-border bg-transparent px-3 py-2 text-sm disabled:opacity-50"
        />
        <button onClick={submit} disabled={c.isSending || c.isClosing} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">Send</button>
      </div>
    </div>
  );
}
