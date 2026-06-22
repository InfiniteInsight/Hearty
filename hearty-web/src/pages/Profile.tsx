import { useState } from "react";
import { useHealthProfile, useHealthProfileDefaults, useSaveHealthProfile } from "../hooks/useHealthProfile";
import ProfileSection from "../components/profile/ProfileSection";
import type {
  AllergenEntry, IntoleranceEntry, ConditionEntry, DietaryProtocolEntry,
  HealthProfilePutRequest, Severity,
} from "@/types/api";

const DISCLAIMER = "Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional.";
const SEVERITIES: Severity[] = ["mild", "moderate", "severe"];

export default function Profile() {
  const profile = useHealthProfile();
  const defaults = useHealthProfileDefaults();
  const save = useSaveHealthProfile();
  const [edits, setEdits] = useState<Partial<HealthProfilePutRequest>>({});
  const [msg, setMsg] = useState<string | null>(null);

  const draft: HealthProfilePutRequest | null = profile.data
    ? {
        allergens: edits.allergens ?? profile.data.allergens,
        intolerances: edits.intolerances ?? profile.data.intolerances,
        conditions: edits.conditions ?? profile.data.conditions,
        dietary_protocols: edits.dietary_protocols ?? profile.data.dietary_protocols,
      }
    : null;

  async function onSave() {
    if (!draft) return;
    setMsg(null);
    try { await save.mutateAsync(draft); setEdits({}); setMsg("Saved."); }
    catch { setMsg("Couldn't save."); }
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Profile</h1>

      {/* Persistent, non-dismissable disclaimer */}
      <div className="rounded-2xl border border-warn/40 bg-warn/10 p-3 text-sm text-warn">{DISCLAIMER}</div>

      {profile.isPending && <p className="text-text-faint">Loading…</p>}
      {profile.isError && <p className="text-sm text-accent-red">Couldn't load your profile.</p>}

      {draft && (
        <>
          <ProfileSection<AllergenEntry>
            title="Allergens"
            entries={draft.allergens}
            onChange={(allergens) => setEdits((e) => ({ ...e, allergens }))}
            newEntry={() => ({ name: "", severity: "mild", confirmed_by_doctor: false })}
            suggestions={defaults.data?.allergens}
            suggestionToEntry={(name) => ({ name, severity: "mild", confirmed_by_doctor: false })}
            renderFields={(a, update) => (
              <>
                <input aria-label="allergen name" value={a.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <select aria-label="allergen severity" value={a.severity} onChange={(e) => update({ severity: e.target.value as Severity })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
                  {SEVERITIES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                <input aria-label="allergen reaction" value={a.reaction ?? ""} onChange={(e) => update({ reaction: e.target.value || undefined })} placeholder="Reaction (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={a.confirmed_by_doctor} onChange={(e) => update({ confirmed_by_doctor: e.target.checked })} />
                  Confirmed by doctor
                </label>
                <input aria-label="allergen notes" value={a.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<IntoleranceEntry>
            title="Intolerances"
            entries={draft.intolerances}
            onChange={(intolerances) => setEdits((e) => ({ ...e, intolerances }))}
            newEntry={() => ({ name: "" })}
            suggestions={defaults.data?.intolerances}
            suggestionToEntry={(name) => ({ name })}
            renderFields={(it, update) => (
              <>
                <input aria-label="intolerance name" value={it.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <select aria-label="intolerance severity" value={it.severity ?? ""} onChange={(e) => update({ severity: (e.target.value || undefined) as Severity | undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
                  <option value="">unset</option>
                  {SEVERITIES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                <input aria-label="intolerance threshold" value={it.threshold ?? ""} onChange={(e) => update({ threshold: e.target.value || undefined })} placeholder="Threshold (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="intolerance notes" value={it.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<ConditionEntry>
            title="Conditions"
            entries={draft.conditions}
            onChange={(conditions) => setEdits((e) => ({ ...e, conditions }))}
            newEntry={() => ({ name: "", diagnosed: false })}
            suggestions={defaults.data?.conditions}
            suggestionToEntry={(name) => ({ name, diagnosed: false })}
            renderFields={(c, update) => (
              <>
                <input aria-label="condition name" value={c.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={c.diagnosed} onChange={(e) => update({ diagnosed: e.target.checked })} />
                  Diagnosed
                </label>
                <input aria-label="condition diagnosis year" type="number" value={c.diagnosis_year ?? ""} onChange={(e) => update({ diagnosis_year: e.target.value ? Number(e.target.value) : undefined })} placeholder="Year (optional)" className="w-28 rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="condition notes" value={c.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<DietaryProtocolEntry>
            title="Dietary protocols"
            entries={draft.dietary_protocols}
            onChange={(dietary_protocols) => setEdits((e) => ({ ...e, dietary_protocols }))}
            newEntry={() => ({ name: "", active: true })}
            suggestions={defaults.data?.dietary_protocols}
            suggestionToEntry={(name) => ({ name, active: true })}
            renderFields={(p, update) => (
              <>
                <input aria-label="protocol name" value={p.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={p.active} onChange={(e) => update({ active: e.target.checked })} />
                  Active
                </label>
                <input aria-label="protocol started" type="date" value={p.started ?? ""} onChange={(e) => update({ started: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="protocol phase" value={p.phase ?? ""} onChange={(e) => update({ phase: e.target.value || undefined })} placeholder="Phase (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="protocol notes" value={p.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <div className="flex items-center gap-3">
            <button onClick={onSave} disabled={save.isPending} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">{save.isPending ? "Saving…" : "Save profile"}</button>
            {msg && <span className="text-sm text-text-muted">{msg}</span>}
          </div>
        </>
      )}
    </div>
  );
}
