# Starter knowledge-base corpus (DRAFT — owner review required)

This directory holds a **draft** starter corpus for Hearty's RAG feature
(Spec 11 Layer 1, the `knowledge_base` table). It is a reviewable draft, not a
loaded dataset.

- **Nothing has been inserted into any database.** These are plain files.
- The entries are framed as **observed associations and general dietary
  patterns, not diagnoses or medical advice** — matching the app's guardrail
  (the AI surfaces correlations, never tells a user what to do).
- Every entry covers textbook-level, conservatively-worded GI/dietary
  knowledge. **No study citations, author names, journal names, percentages, or
  specific statistics were invented.** If you want citations, add real ones (see
  the VERIFY checklist below).

## Files

| File           | What it is                                                            |
| -------------- | --------------------------------------------------------------------- |
| `seed.json`    | A JSON array of entries: `{ title, content, conditions[], source }`.  |
| `load_seed.py` | A manual loader you run by hand. Dry-run by default; writes only with `--confirm`. |
| `README.md`    | This file.                                                            |

### How `conditions` scoping works

- An entry tagged with one or more **condition slugs** (`ibs`, `gerd`, `celiac`,
  `histamine`, `lactose`) only surfaces to users who have a matching condition.
- An entry with an **empty** `conditions` array (`[]`) is general nutrition and
  surfaces to everyone.

Tags in this draft use only those five lowercase slugs.

## How to load it (only after you've reviewed every entry)

The loader uses the **same env vars as the app**. Make sure they point where you
intend — the loader writes to whatever `SUPABASE_URL` is set to.

Required env vars (for the live write only):

```
SUPABASE_URL          # project URL — THIS DECIDES WHICH DB GETS WRITTEN TO
SUPABASE_SERVICE_KEY  # service-role key for the knowledge_base table
GEMINI_API_KEY        # Google AI Studio key, used to embed each entry's content
```

Run it from a context where the `app` package is importable (e.g. inside
`hearty-api/`):

```bash
cd hearty-api

# 1) DRY RUN — parses + validates seed.json and prints what WOULD be inserted.
#    Needs no creds and makes no network calls. Nothing is written.
python scripts/knowledge_seed/load_seed.py

# 2) LIVE WRITE — embeds each entry (Gemini) and inserts rows. Prompts for a
#    typed 'yes' confirmation after printing a warning.
python scripts/knowledge_seed/load_seed.py --confirm
```

Notes:

- The loader has **no de-duplication**. Running `--confirm` twice inserts the
  corpus twice. Load once, or clear the table first.
- Each entry is embedded with Gemini at load time (one embedding call per row),
  so `--confirm` requires `GEMINI_API_KEY` and network access.

## `# VERIFY` — owner checklist before loading

A human must review **every** entry for medical accuracy before loading. This
draft was written conservatively, but it has not been fact-checked by a clinician.

- [ ] Read every entry in `seed.json` end to end.
- [ ] Confirm each claim is accurate, current, and conservatively worded.
- [ ] Confirm each entry is an **observation/association**, not a diagnosis or a
      directive ("commonly associated with", "many people with X find…" — never
      "you should", "avoid", or "X causes Y").
- [ ] Confirm there are **no fabricated** statistics, percentages, study names,
      authors, or journals (there should be none — verify).
- [ ] Confirm each `conditions` tag is correct and uses an allowed slug
      (`ibs`, `gerd`, `celiac`, `histamine`, `lactose`, or `[]` for general).
- [ ] Consider adding **real citations** (e.g. NHS, NIH, a clinical guideline)
      to the `content` of entries where a source would strengthen them.
- [ ] Edit or remove anything you are not comfortable surfacing to users.
- [ ] Confirm `SUPABASE_URL` points at the intended database before `--confirm`.
- [ ] Run the dry run, review the printed summary, then run `--confirm` once.
