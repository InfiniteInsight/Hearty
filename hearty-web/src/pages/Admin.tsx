import { useState } from "react";
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings } from "../hooks/useAdmin";
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
      <SignupPolicy />
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
