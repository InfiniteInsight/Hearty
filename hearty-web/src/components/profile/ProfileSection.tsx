import type { ReactNode } from "react";

export default function ProfileSection<T>({
  title,
  entries,
  onChange,
  newEntry,
  renderFields,
  suggestions,
  suggestionToEntry,
}: {
  title: string;
  entries: T[];
  onChange: (entries: T[]) => void;
  newEntry: () => T;
  renderFields: (entry: T, update: (patch: Partial<T>) => void) => ReactNode;
  suggestions?: string[];
  suggestionToEntry?: (name: string) => T;
}) {
  function update(index: number, patch: Partial<T>) {
    onChange(entries.map((e, i) => (i === index ? { ...e, ...patch } : e)));
  }
  function remove(index: number) {
    onChange(entries.filter((_, i) => i !== index));
  }

  return (
    <section className="rounded-2xl border border-surface-border bg-surface p-4">
      <h2 className="mb-3 text-sm text-text-muted">{title}</h2>

      <div className="flex flex-col gap-3">
        {entries.map((entry, i) => (
          <div key={i} className="rounded-xl border border-surface-border p-3">
            <div className="flex flex-col gap-2">{renderFields(entry, (patch) => update(i, patch))}</div>
            <button onClick={() => remove(i)} className="mt-2 text-xs text-accent-red underline">Remove</button>
          </div>
        ))}
        {entries.length === 0 && <p className="text-text-faint text-sm">None added.</p>}
      </div>

      <button onClick={() => onChange([...entries, newEntry()])} className="mt-3 rounded-lg border border-surface-border px-3 py-1 text-sm">
        Add {title.toLowerCase()}
      </button>

      {suggestions && suggestions.length > 0 && suggestionToEntry && (
        <div className="mt-3 flex flex-wrap gap-1">
          {suggestions.map((name) => (
            <button
              key={name}
              onClick={() => onChange([...entries, suggestionToEntry(name)])}
              className="rounded-full border border-surface-border px-2 py-0.5 text-xs text-text-muted hover:text-text"
            >
              {name}
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
