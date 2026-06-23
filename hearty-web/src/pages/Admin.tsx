import { useState } from "react";
import { useAdminUsers, useAdminActions } from "../hooks/useAdmin";
import type { AdminUser } from "@/types/api";

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
  return (
    <div className="flex gap-2">
      {(status == null || status === "revoked") && (
        <button
          disabled={busy}
          onClick={status === "revoked" ? actions.onReactivate : actions.onGrant}
          className="rounded px-3 py-1 text-xs bg-brand text-white hover:opacity-80 disabled:opacity-40"
        >
          {status === "revoked" ? "Reactivate" : "Grant"}
        </button>
      )}
      {status === "active" && (
        <>
          <button
            disabled={busy}
            onClick={actions.onRevoke}
            className="rounded px-3 py-1 text-xs bg-accent-red text-white hover:opacity-80 disabled:opacity-40"
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
                <tr key={user.user_id} className="border-b border-surface-border last:border-0 hover:bg-surface-hover">
                  <td className="px-4 py-3">{user.email}</td>
                  <td className="px-4 py-3 text-text-muted">{formatDate(user.created_at)}</td>
                  <td className="px-4 py-3">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                      user.license?.status === "active" ? "bg-emerald-100 text-emerald-700" :
                      user.license?.status === "revoked" ? "bg-red-100 text-red-700" :
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
