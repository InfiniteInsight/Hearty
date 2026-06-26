#!/usr/bin/env python3
"""Manual loader for the starter knowledge-base corpus (RAG Spec 11 Layer 1).

THE OWNER RUNS THIS BY HAND. It is intentionally NOT wired into CI, deploys, or
the app. Read scripts/knowledge_seed/README.md first.

Behaviour:
  * No flag        -> DRY RUN. Parses seed.json, validates it, and prints exactly
                      what WOULD be inserted. Touches no creds and no network.
  * --confirm      -> LIVE WRITE. Embeds each entry's content (Gemini) and inserts
                      a row into the knowledge_base table of whatever database the
                      environment currently points at.

Run it from anywhere, but with the hearty-api package importable (i.e. run it
with `hearty-api/` on PYTHONPATH, e.g. from inside the hearty-api directory):

    cd hearty-api
    python scripts/knowledge_seed/load_seed.py            # dry run
    python scripts/knowledge_seed/load_seed.py --confirm  # actually writes

Required env vars for --confirm (same ones the app uses):
    SUPABASE_URL          - the project URL (THIS DECIDES WHICH DB IS WRITTEN TO)
    SUPABASE_SERVICE_KEY  - service-role key for the knowledge_base table
    GEMINI_API_KEY        - Google AI Studio key, used to embed each entry
"""

import argparse
import json
import sys
from pathlib import Path

# seed.json lives next to this script, regardless of the current working dir.
SEED_PATH = Path(__file__).parent / "seed.json"

# The exact keys each seed entry may carry. add_entry() takes title/content/
# conditions/source (source_id defaults to None); seed.json must not smuggle in
# fields the table/loader don't handle.
ALLOWED_KEYS = {"title", "content", "conditions", "source"}


def load_seed() -> list[dict]:
    """Read and validate seed.json. Raises on any structural problem so a bad
    corpus is caught during the dry run rather than half-inserted live."""
    if not SEED_PATH.exists():
        sys.exit(f"ERROR: seed file not found at {SEED_PATH}")

    with SEED_PATH.open(encoding="utf-8") as f:
        entries = json.load(f)

    if not isinstance(entries, list) or not entries:
        sys.exit("ERROR: seed.json must be a non-empty JSON array.")

    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            sys.exit(f"ERROR: entry #{i} is not an object.")
        extra = set(entry) - ALLOWED_KEYS
        if extra:
            sys.exit(f"ERROR: entry #{i} has unexpected keys: {sorted(extra)}")
        if not entry.get("title") or not entry.get("content"):
            sys.exit(f"ERROR: entry #{i} is missing a title or content.")
        if not isinstance(entry.get("conditions", []), list):
            sys.exit(f"ERROR: entry #{i} 'conditions' must be a list.")

    return entries


def print_summary(entries: list[dict]) -> None:
    """Print the corpus and a per-condition-tag breakdown."""
    print(f"\nLoaded {len(entries)} entries from {SEED_PATH}\n")

    tally: dict[str, int] = {}
    for entry in entries:
        conditions = entry.get("conditions") or []
        keys = conditions if conditions else ["(general / untagged)"]
        for key in keys:
            tally[key] = tally.get(key, 0) + 1

    print("Breakdown by condition tag (an entry with N tags counts in N rows):")
    for tag in sorted(tally):
        print(f"  {tag:>22} : {tally[tag]}")
    print()

    for i, entry in enumerate(entries, 1):
        conditions = entry.get("conditions") or []
        tags = ", ".join(conditions) if conditions else "[] general"
        print(f"  {i:>2}. ({tags})  {entry['title']}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load the starter knowledge-base corpus (dry-run by default).")
    parser.add_argument(
        "--confirm", action="store_true",
        help="Actually embed and insert rows. WITHOUT this flag the script only "
             "prints what it would do and exits.")
    args = parser.parse_args()

    entries = load_seed()
    print_summary(entries)

    if not args.confirm:
        print("DRY RUN: nothing was written. Re-run with --confirm to insert.\n")
        return

    # ---- Live write path. Only here do we touch creds and the network. ----
    print("=" * 70)
    print("!! WARNING: --confirm given. This will WRITE to the live database !!")
    print("!! pointed at by SUPABASE_URL, embedding every entry via Gemini.   !!")
    print("!! There is no built-in de-duplication: running this twice inserts !!")
    print("!! the corpus twice. Make sure these entries are reviewed and that !!")
    print("!! SUPABASE_URL points where you intend.                          !!")
    print("=" * 70)
    reply = input("Type 'yes' to proceed: ").strip().lower()
    if reply != "yes":
        sys.exit("Aborted. Nothing was written.")

    # Imported lazily: app.services.knowledge builds a Supabase client at import
    # time (needs creds) and add_entry() makes a network embedding call. Keeping
    # the import here means a dry run needs neither creds nor network.
    from app.services.knowledge import add_entry

    inserted = 0
    for i, entry in enumerate(entries, 1):
        try:
            row = add_entry(
                title=entry["title"],
                content=entry["content"],
                conditions=entry.get("conditions") or [],
                source=entry.get("source", "manual"),
            )
            inserted += 1
            print(f"  inserted {i:>2}/{len(entries)}  id={row.get('id')}  {entry['title']}")
        except Exception as e:  # noqa: BLE001 - surface and keep going
            print(f"  FAILED   {i:>2}/{len(entries)}  {entry['title']}: {e}")

    print(f"\nDone. Inserted {inserted}/{len(entries)} entries.\n")


if __name__ == "__main__":
    main()
