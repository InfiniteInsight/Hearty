import { useState } from "react";
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings, useHealth, useTestLlm, useKnowledge, useKnowledgeActions, usePromptOverlays, usePromptOverlayVersions, usePromptOverlayActions } from "../hooks/useAdmin";
import type { AdminUser, ProvisioningMode } from "@/types/api";

function formatDate(s: string | null | undefined) {
  if (!s) return "—";
  try { return new Date(s).toLocaleDateString(); } catch { return s; }
}

function LicenseActions({ user, busy, actions }: {
  user: AdminUser;
  busy: boolean;
  actions: {
    onGrant: () => void;
    onRevoke: () => void;
    onReactivate: () => void;
    onEditExpiry: (id: string) => void;
  };
}) {
  const status = user.license?.status;
  const hasLicense = status != null;
  // "expired" is a derived state over a stored-active row, so it shares active's
  // actions (Revoke / Edit expiry — extend to restore). Exhaustive: every state
  // has an action.
  const activeLike = status === "active" || status === "expired";
  return (
    <div className="flex gap-2">
      {!hasLicense && (
        <button
          disabled={busy}
          onClick={actions.onGrant}
          className="rounded px-3 py-1 text-xs bg-brand text-black hover:opacity-80 disabled:opacity-40"
        >
          Grant
        </button>
      )}
      {status === "revoked" && (
        <button
          disabled={busy}
          onClick={actions.onReactivate}
          className="rounded px-3 py-1 text-xs bg-brand text-black hover:opacity-80 disabled:opacity-40"
        >
          Reactivate
        </button>
      )}
      {activeLike && (
        <>
          <button
            disabled={busy}
            onClick={actions.onRevoke}
            className="rounded px-3 py-1 text-xs bg-accent-red text-black hover:opacity-80 disabled:opacity-40"
          >
            Revoke
          </button>
          <button
            disabled={busy}
            onClick={() => actions.onEditExpiry(user.user_id)}
            className="rounded px-3 py-1 text-xs border border-surface-border text-text-muted hover:text-text disabled:opacity-40"
          >
            Edit expiry
          </button>
        </>
      )}
    </div>
  );
}

function SignupPolicy() {
  const settings = useAppSettings();
  const update = useUpdateAppSettings();
  const [mode, setMode] = useState<ProvisioningMode>("open");
  const [trialDays, setTrialDays] = useState(14);
  // Seed local state from the server once. A useState flag (not a ref) — this
  // project's lint rule forbids accessing refs during render.
  const [loaded, setLoaded] = useState(false);
  if (settings.isSuccess && !loaded) {
    setMode(settings.data.provisioning_mode);
    setTrialDays(settings.data.trial_days);
    setLoaded(true);
  }
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Signup policy</h2>
      <p className="text-xs text-text-faint">Applies to future signups only. Existing users are unaffected.</p>
      <div className="flex flex-wrap items-end gap-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-text-muted">Signup policy</span>
          <select
            aria-label="Signup policy"
            value={mode}
            onChange={(e) => setMode(e.target.value as ProvisioningMode)}
            className="rounded border border-surface-border bg-background px-2 py-1 text-text"
          >
            <option value="open">Open — auto-grant access</option>
            <option value="trial">Trial — time-limited access</option>
            <option value="paywall">Paywall — gated until granted</option>
          </select>
        </label>
        {mode === "trial" && (
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-text-muted">Trial days</span>
            <input
              type="number"
              min={1}
              value={trialDays}
              onChange={(e) => setTrialDays(Number(e.target.value))}
              className="w-24 rounded border border-surface-border bg-background px-2 py-1 text-text"
            />
          </label>
        )}
        <button
          disabled={update.isPending}
          onClick={() => update.mutate({ provisioning_mode: mode, trial_days: trialDays })}
          className="rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40"
        >
          Save policy
        </button>
      </div>
      {update.isError && <p className="text-sm text-accent-red">Failed to save policy. Try again.</p>}
      {update.isSuccess && <p className="text-sm text-good">Policy saved.</p>}
    </div>
  );
}

function pillClass(status: string): string {
  if (status === "ok") return "bg-good/15 text-good";
  if (status === "idle") return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red"; // down / degraded
}

function SystemHealth() {
  const health = useHealth();
  const test = useTestLlm();
  const h = health.data;
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-xl">System health</h2>
        <div className="flex gap-2">
          <button onClick={() => { test.reset(); health.refetch(); }} disabled={health.isFetching}
            className="rounded px-3 py-1 text-xs border border-surface-border text-text-muted hover:text-text disabled:opacity-40">
            Re-check
          </button>
          <button onClick={() => test.mutate()} disabled={test.isPending || health.isFetching}
            className="rounded px-3 py-1 text-xs bg-brand text-black hover:opacity-80 disabled:opacity-40">
            {test.isPending ? "Testing…" : "Test LLM"}
          </button>
        </div>
      </div>
      {health.isPending && <p className="text-text-faint text-sm">Checking…</p>}
      {health.isError && <p className="text-accent-red text-sm">Couldn't load health.</p>}
      {h && (
        <div className="flex flex-col divide-y divide-surface-border">
          <HealthRow label="Backend" status={h.backend.status} detail={`rev ${h.backend.revision} · v${h.backend.version}`} />
          <HealthRow label="Database" status={h.supabase.status}
            detail={h.supabase.status === "ok" ? `${h.supabase.latency_ms ?? "—"} ms` : (h.supabase.error ?? "")} />
          <HealthRow label="AI / LLM" status={h.llm.status}
            detail={h.llm.status === "degraded" ? (h.llm.last_error ?? "") :
                    h.llm.status === "idle" ? "no recent calls" : `last ok · ${h.llm.model ?? ""}`} />
        </div>
      )}
      {test.isError && <p className="text-accent-red text-sm">LLM test failed.</p>}
      {test.data && (
        <p className={`text-sm ${test.data.ok ? "text-good" : "text-accent-red"}`}>
          {test.data.ok ? `LLM ok (${test.data.latency_ms} ms)` : `LLM test failed: ${test.data.error}`}
        </p>
      )}
    </div>
  );
}

function HealthRow({ label, status, detail }: { label: string; status: string; detail: string }) {
  return (
    <div className="flex items-center justify-between py-2">
      <span className="text-sm text-text">{label}</span>
      <div className="flex items-center gap-3">
        <span className="text-xs text-text-muted">{detail}</span>
        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${pillClass(status)}`}>{status}</span>
      </div>
    </div>
  );
}

function KnowledgeBase() {
  const entries = useKnowledge();
  const actions = useKnowledgeActions();
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [conditions, setConditions] = useState("");
  // setActive/remove are single-instance mutations, so one in-flight call
  // disables every row's buttons — same global-busy approach as the subscriber
  // table; prevents double-fire on toggle/delete.
  const rowBusy = actions.setActive.isPending || actions.remove.isPending;

  function submit() {
    const conds = conditions.split(",").map((c) => c.trim()).filter(Boolean);
    actions.create.mutate(
      { title: title || undefined, content, conditions: conds },
      { onSuccess: () => { setTitle(""); setContent(""); setConditions(""); } },
    );
  }

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Knowledge base</h2>
      <p className="text-xs text-text-faint">
        Curated research the AI grounds its explanations in. Untagged entries apply to everyone;
        tag with conditions (comma-separated) to scope to those users.
      </p>

      <div className="flex flex-col gap-2">
        <input aria-label="Title" placeholder="Title (optional)" value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <textarea aria-label="Content" placeholder="Research excerpt" value={content} rows={3}
          onChange={(e) => setContent(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <input aria-label="Conditions" placeholder="Conditions, comma-separated (e.g. gerd, ibs)"
          value={conditions} onChange={(e) => setConditions(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <button disabled={!content || actions.create.isPending} onClick={submit}
          className="self-start rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40">
          Add entry
        </button>
      </div>
      {actions.create.isError && (
        <p className="text-sm text-accent-red">Failed to add entry (embedding may have failed).</p>
      )}

      {entries.isPending && <p className="text-text-faint text-sm">Loading…</p>}
      {entries.data && entries.data.entries.length === 0 && (
        <p className="text-text-faint text-sm">No entries yet.</p>
      )}
      {entries.data && entries.data.entries.length > 0 && (
        <div className="flex flex-col divide-y divide-surface-border">
          {entries.data.entries.map((e) => (
            <div key={e.id} className="flex items-center justify-between py-2 gap-3">
              <div className="flex flex-col">
                <span className="text-sm text-text">{e.title || "(untitled)"}</span>
                <span className="text-xs text-text-faint">
                  {e.source}{e.conditions.length ? ` · ${e.conditions.join(", ")}` : ""}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <button disabled={rowBusy}
                  onClick={() => actions.setActive.mutate({ id: e.id, active: !e.active })}
                  className="rounded px-2 py-0.5 text-xs border border-surface-border text-text-muted hover:text-text disabled:opacity-40">
                  {e.active ? "Active" : "Inactive"}
                </button>
                <button disabled={rowBusy} onClick={() => actions.remove.mutate(e.id)}
                  className="rounded px-2 py-0.5 text-xs bg-accent-red text-black hover:opacity-80 disabled:opacity-40">
                  Delete
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

const OVERLAY_SURFACES: { surface: string; label: string; help: string }[] = [
  { surface: "summary", label: "Weekly summary", help: "How Hearty writes your weekly summary." },
  { surface: "trends_conversation", label: "Trends conversation", help: "How Hearty runs the monthly trends check-in." },
];

function OverlayEditor({ surface, label, help }: { surface: string; label: string; help: string }) {
  const overlays = usePromptOverlays();
  const actions = usePromptOverlayActions();
  const current = overlays.data?.overlays.find((o) => o.surface === surface);
  const [text, setText] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const versions = usePromptOverlayVersions(surface, showHistory);
  if (overlays.isSuccess && !loaded) { setText(current?.guidance ?? ""); setLoaded(true); }

  return (
    <div className="flex flex-col gap-2 border-t border-surface-border pt-3 first:border-t-0 first:pt-0">
      <div className="flex items-center justify-between">
        <span className="text-sm text-text">{label}</span>
        <button onClick={() => setShowHistory((v) => !v)}
          className="text-xs text-text-muted hover:text-text">
          {showHistory ? "Hide history" : "History"}
        </button>
      </div>
      <p className="text-xs text-text-faint">{help} The structural rules and the "observations, not diagnoses" guardrail always apply.</p>
      <textarea aria-label={`${surface} overlay`} value={text} rows={3}
        onChange={(e) => setText(e.target.value)}
        placeholder="Optional guidance (tone, emphasis, things to mention or avoid)…"
        className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
      <button disabled={actions.save.isPending}
        onClick={() => actions.save.mutate({ surface, guidance: text })}
        className="self-start rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40">
        Save {label.toLowerCase()}
      </button>
      {actions.save.isError && <p className="text-sm text-accent-red">Failed to save.</p>}
      {showHistory && versions.data && (
        <div className="flex flex-col divide-y divide-surface-border">
          {versions.data.versions.length === 0 && <p className="text-xs text-text-faint">No history yet.</p>}
          {versions.data.versions.map((v) => (
            <div key={v.id} className="flex items-center justify-between py-1.5 gap-3">
              <span className="text-xs text-text-faint truncate">
                {new Date(v.created_at).toLocaleString()} · {v.guidance ? v.guidance.slice(0, 60) : "(empty)"}
              </span>
              <button disabled={actions.revert.isPending}
                onClick={() => actions.revert.mutate({ surface, versionId: v.id }, { onSuccess: () => { setText(v.guidance); } })}
                className="rounded px-2 py-0.5 text-xs border border-surface-border text-text-muted hover:text-text disabled:opacity-40">
                Revert
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function PromptTuning() {
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Prompt tuning</h2>
      <p className="text-xs text-text-faint">Tune how Hearty talks. Edits layer on top of the locked core prompts and apply to the next AI call.</p>
      {OVERLAY_SURFACES.map((s) => <OverlayEditor key={s.surface} {...s} />)}
    </div>
  );
}

export default function Admin() {
  const list = useAdminUsers();
  const a = useAdminActions();
  const [err, setErr] = useState<string | null>(null);
  const [editingExpiry, setEditingExpiry] = useState<{ id: string; value: string } | null>(null);

  const busy = a.grant.isPending || a.revoke.isPending || a.reactivate.isPending || a.update.isPending;

  function run(p: Promise<unknown>) {
    setErr(null);
    p.catch(() => setErr("Something went wrong. Try again."));
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <h1 className="font-display text-3xl">Subscribers</h1>
      <SystemHealth />
      <SignupPolicy />
      <KnowledgeBase />
      <PromptTuning />
      {err && <p className="text-sm text-accent-red">{err}</p>}
      {list.isPending && <p className="text-text-faint">Loading…</p>}
      {list.isError && <p className="text-sm text-accent-red">Couldn't load subscribers.</p>}
      {list.isSuccess && list.data.users.length === 0 && (
        <p className="text-text-faint">No subscribers yet.</p>
      )}
      {list.isSuccess && list.data.users.length > 0 && (
        <div className="rounded-2xl border border-surface-border bg-surface overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-border text-left text-text-muted">
                <th className="px-4 py-3 font-medium">Email</th>
                <th className="px-4 py-3 font-medium">Joined</th>
                <th className="px-4 py-3 font-medium">License</th>
                <th className="px-4 py-3 font-medium">Expiry</th>
                <th className="px-4 py-3 font-medium">Tier</th>
                <th className="px-4 py-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {list.data.users.map((user) => (
                <tr key={user.user_id} className="border-b border-surface-border last:border-0 hover:bg-white/5">
                  <td className="px-4 py-3">{user.email}</td>
                  <td className="px-4 py-3 text-text-muted">{formatDate(user.created_at)}</td>
                  <td className="px-4 py-3">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                      user.license?.status === "active" ? "bg-good/15 text-good" :
                      user.license?.status === "revoked" ? "bg-accent-red/15 text-accent-red" :
                      user.license?.status === "expired" ? "bg-warn/15 text-warn" :
                      "bg-surface-border text-text-muted"
                    }`}>
                      {user.license?.status ?? "none"}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-text-muted">
                    {editingExpiry?.id === user.user_id ? (
                      <div className="flex gap-2 items-center">
                        <input
                          type="date"
                          value={editingExpiry.value}
                          onChange={(e) => setEditingExpiry({ id: user.user_id, value: e.target.value })}
                          className="rounded border border-surface-border bg-background px-2 py-0.5 text-xs text-text"
                        />
                        <button
                          disabled={busy}
                          onClick={() => {
                            if (editingExpiry.value) {
                              run(a.update.mutateAsync({ id: user.user_id, body: { expires_at: new Date(editingExpiry.value).toISOString() } }));
                            }
                            setEditingExpiry(null);
                          }}
                          className="text-xs text-brand hover:underline"
                        >Save</button>
                        <button onClick={() => setEditingExpiry(null)} className="text-xs text-text-muted hover:text-text">Cancel</button>
                      </div>
                    ) : formatDate(user.license?.expires_at)}
                  </td>
                  <td className="px-4 py-3 text-text-muted">{user.license?.tier ?? "—"}</td>
                  <td className="px-4 py-3">
                    <LicenseActions
                      user={user}
                      busy={busy}
                      actions={{
                        onGrant: () => run(a.grant.mutateAsync({ user_id: user.user_id })),
                        onRevoke: () => run(a.revoke.mutateAsync(user.user_id)),
                        onReactivate: () => run(a.reactivate.mutateAsync(user.user_id)),
                        onEditExpiry: (id) => setEditingExpiry({ id, value: "" }),
                      }}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
