import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePreferences, useSavePreferences } from "../hooks/usePreferences";
import { api } from "../lib/api";
import { signOut } from "../lib/auth";
import { supabase } from "../lib/supabase";
import { saveBlob } from "../lib/download";
import type { UserPreferences } from "@/types/api";

const CONFIRM_PHRASE = "delete my account";

export default function Settings() {
  const navigate = useNavigate();
  const prefsQuery = usePreferences();
  const save = useSavePreferences();
  const [edits, setEdits] = useState<Partial<UserPreferences>>({});
  const [email, setEmail] = useState<string | null>(null);
  const [showDelete, setShowDelete] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // The editable draft is the loaded prefs with local edits layered on top — no
  // effect needed. Saving the full object preserves untouched fields (health,
  // voice) on PUT (which is a full replace).
  const draft: UserPreferences | null = prefsQuery.data ? { ...prefsQuery.data, ...edits } : null;
  useEffect(() => { supabase.auth.getSession().then(({ data }) => setEmail(data.session?.user?.email ?? null)); }, []);

  function set<K extends keyof UserPreferences>(key: K, value: UserPreferences[K]) {
    setEdits((e) => ({ ...e, [key]: value }));
  }

  async function onSave() {
    if (!draft) return;
    setMsg(null);
    try { await save.mutateAsync(draft); setMsg("Saved."); }
    catch { setMsg("Couldn't save."); }
  }

  async function exportAll() {
    setMsg(null);
    try { const dl = await api.exportJson({}); saveBlob(dl.blob, dl.filename); }
    catch { setMsg("Couldn't export your data."); }
  }

  async function confirmDelete() {
    if (confirmText !== CONFIRM_PHRASE || busy) return;
    setBusy(true);
    try { await api.deleteAccount(); await signOut(); navigate("/login", { replace: true }); }
    catch { setMsg("Couldn't delete your account."); setBusy(false); }
  }

  if (prefsQuery.isPending) return <p className="text-text-faint">Loading…</p>;
  if (prefsQuery.isError || !draft) return <p className="text-sm text-accent-red">Couldn't load settings.</p>;

  const toggle = (key: keyof UserPreferences, label: string) => (
    <label className="flex items-center justify-between gap-3 py-1 text-sm">
      <span>{label}</span>
      <input type="checkbox" checked={Boolean(draft[key])} onChange={(e) => set(key, e.target.checked as never)} />
    </label>
  );

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Settings</h1>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Notifications</h2>
        {toggle("post_meal_nudge_enabled", "Post-meal nudge")}
        {toggle("daily_checkin_enabled", "Daily check-in")}
        {toggle("trends_conversation_enabled", "Trends conversation")}
        {toggle("weekly_digest_enabled", "Weekly digest")}
        {toggle("sync_error_alerts_enabled", "Sync error alerts")}
        <label className="flex items-center justify-between gap-3 py-1 text-sm">
          <span>Nudge delay (minutes)</span>
          <input type="number" value={draft.nudge_delay_minutes} onChange={(e) => set("nudge_delay_minutes", Number(e.target.value))} className="w-20 rounded-lg border border-surface-border bg-transparent px-2 py-1" />
        </label>
        <label className="flex items-center justify-between gap-3 py-1 text-sm">
          <span>Conversation style</span>
          <select value={draft.conversation_style} onChange={(e) => set("conversation_style", e.target.value as UserPreferences["conversation_style"])} className="rounded-lg border border-surface-border bg-surface px-2 py-1">
            <option value="warm">warm</option>
            <option value="concise">concise</option>
          </select>
        </label>
      </section>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Check-in slots</h2>
        {toggle("morning_checkin_enabled", "Morning")}
        {toggle("midday_checkin_enabled", "Midday")}
        {toggle("evening_checkin_enabled", "Evening")}
      </section>

      <div className="flex items-center gap-3">
        <button onClick={onSave} disabled={save.isPending} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">{save.isPending ? "Saving…" : "Save"}</button>
        {msg && <span className="text-sm text-text-muted">{msg}</span>}
      </div>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Account</h2>
        <div className="font-mono-data text-xs text-text-faint">{email ?? "—"}</div>
        <div className="mt-3 flex flex-wrap gap-2">
          <button onClick={() => signOut().then(() => navigate("/login", { replace: true }))} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Sign out</button>
          <button onClick={exportAll} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Export all data</button>
          <button onClick={() => setShowDelete(true)} className="rounded-lg border border-accent-red/50 px-3 py-1 text-sm text-accent-red">Delete account</button>
        </div>
      </section>

      {showDelete && (
        <div className="rounded-2xl border border-accent-red/50 bg-surface p-4">
          <p className="text-sm text-text-muted">This permanently deletes your account and all data. Type <span className="font-mono-data text-accent-red">{CONFIRM_PHRASE}</span> to confirm.</p>
          <input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder={CONFIRM_PHRASE} className="mt-2 w-full rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          <div className="mt-2 flex gap-2">
            <button onClick={confirmDelete} disabled={confirmText !== CONFIRM_PHRASE || busy} className="rounded-lg bg-accent-red px-3 py-1 text-sm text-black disabled:opacity-40">Delete my account</button>
            <button onClick={() => { setShowDelete(false); setConfirmText(""); }} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}
