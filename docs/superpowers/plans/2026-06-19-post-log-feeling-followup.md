# Post-Log Feeling Follow-up (text/photo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** After a meal is logged by **text** or **photo**, immediately offer a dismissible, **text-first** "How are you feeling?" prompt (optional note + optional 1–10 discomfort) that records a symptom — matching what the voice path already does in-overlay, but WITHOUT forcing voice. Non-blocking (the meal is already saved). The existing delayed follow-up notification stays as a backup.

**Architecture:** A reusable `FeelingFollowUpSheet` (modal bottom sheet) with a text field + optional severity selector + Save/Skip, that calls the existing `symptomsProvider.logSymptom(description, severity:)` (offline-first → local symptom DAO → sync). Shown right after the text- and photo-log completion paths succeed, before navigating away. No backend changes (symptom logging already exists). Symptom→meal linkage is **time-window correlation** (what the signal engine already uses) — no explicit offline link in v1.

**Tech Stack:** Flutter/Riverpod. Runner: `cd hearty_app && flutter test <path>`; `flutter analyze lib/`.

**Verified facts:**
- `symptomsProvider.logSymptom(String description, {int? severity})` exists (`lib/core/api/providers/symptoms_provider.dart`) → `localSymptomDao.insertLocal(...)` (offline-first). No meal_id param (and no server meal id available offline) → rely on time correlation.
- Text completion: `log_entry_screen.dart` `_logMeal` → on success `_textController.clear()` then `context.pop()`.
- Photo completion: `photo_review_screen.dart` `_save` → on success `context.go('/home')` (this branch already logs with `foods`).
- Existing voice follow-up copy: "How are you feeling? Rate any discomfort 1–10".
- Delayed notification already scheduled for all meals via `meals_provider.logMeal` → `scheduleFollowUpNotification(...)` — leave as-is.

---

## Task 1: `FeelingFollowUpSheet` widget + helper (TDD)

**Files:** Create `hearty_app/lib/features/logging/widgets/feeling_followup_sheet.dart`; Test: `hearty_app/test/features/logging/feeling_followup_sheet_test.dart`.

- [ ] **Step 1:** Build a `FeelingFollowUpSheet` (ConsumerWidget/StatefulWidget) shown as a modal bottom sheet:
  - Title/copy: "How are you feeling?" + helper "Rate any discomfort 1–10 (optional)".
  - A text field (`key: feeling-note-field`) for a free-text note.
  - An optional severity selector 1–10 (`key: feeling-severity`) — e.g. a chip row or slider; null = not set.
  - **Save** button (`key: feeling-save`): calls `ref.read(symptomsProvider.notifier).logSymptom(<note>, severity: <severity-or-null>)`, then closes the sheet. Disabled/no-op if the note is empty AND no severity (nothing to record).
  - **Skip** button (`key: feeling-skip`): closes the sheet, records nothing.
  - Plus a `Future<void> showFeelingFollowUp(BuildContext context)` helper that does `showModalBottomSheet(... isScrollControlled: true, builder: (_) => const FeelingFollowUpSheet())` and completes when dismissed (so callers can `await` it then navigate).
  - Context-after-await safe (`if (context.mounted)` around any post-await use).
- [ ] **Step 2: Widget tests** (override `symptomsProvider`/the notifier with a fake recorder via Riverpod):
  - Entering a note + tapping Save calls `logSymptom` once with that note (and null severity).
  - Selecting a severity + Save passes `severity`.
  - Tapping Skip calls `logSymptom` zero times and closes.
  - Empty note + no severity + Save → no `logSymptom` call (no-op), sheet closes.
- [ ] **Step 3:** `flutter test test/features/logging/feeling_followup_sheet_test.dart`; `flutter analyze lib/features/logging/`.
- [ ] **Step 4: Commit** (`feat(logging): FeelingFollowUpSheet (text-first post-log feeling capture)`).

---

## Task 2: Show the prompt after text- and photo-log completion (TDD/contract)

**Files:** Modify `hearty_app/lib/features/logging/screens/log_entry_screen.dart` (`_logMeal`) and `hearty_app/lib/features/photos/screens/photo_review_screen.dart` (`_save`); Tests: extend their widget tests.

- [ ] **Step 1: Text path** — in `log_entry_screen.dart` `_logMeal`, after a SUCCESSFUL log (where it currently clears + `context.pop()`): `if (mounted) await showFeelingFollowUp(context);` then `if (mounted) context.pop();`. Keep the error path unchanged (no prompt on failure).
- [ ] **Step 2: Photo path** — in `photo_review_screen.dart` `_save`, after the successful `logMeal(...)` (where it currently `context.go('/home')`): `if (mounted) await showFeelingFollowUp(context);` then `if (mounted) context.go('/home')`. Keep the failure SnackBar path unchanged.
- [ ] **Step 3: Tests** — extend each screen's widget test (reuse their fake-client/provider harness; override `symptomsProvider` with a recorder):
  - Text: logging a meal (success) then the feeling sheet appears; entering a note + Save records a symptom; then it pops.
  - Photo: saving (success) shows the feeling sheet; Skip records nothing and proceeds to home.
  - Failure path (meal log errors) → NO feeling sheet shown.
- [ ] **Step 4:** Full `cd hearty_app && flutter test` + `flutter analyze lib/`.
- [ ] **Step 5: Commit** (`feat(logging): offer feeling follow-up after text/photo meal logging`).

> GATE: voice path is untouched (it already has its in-overlay follow-up). Live flow is device-verifiable but the widget tests cover the wiring.

---

## Self-review
- **Scope:** immediate text-first feeling prompt after text/photo logging, reusing `logSymptom`; voice path unchanged; delayed notification retained. No backend changes. Time-based symptom↔meal correlation (no offline link in v1).
- **Non-blocking:** the meal is already saved before the prompt; Skip and empty-input both record nothing; prompt never shows on a failed log.
- **Reuse:** `symptomsProvider.logSymptom` (offline-first) + the established widget-test/provider-override harness.
- **No placeholders:** Task 1 has concrete widget behavior + keys + tests; Task 2 has exact insertion points in the two completion handlers.
