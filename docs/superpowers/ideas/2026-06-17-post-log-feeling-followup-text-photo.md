# Idea: Offer the "how are you feeling?" follow-up after TEXT / PHOTO logging (not just voice)

**Status:** Captured (not yet brainstormed). Raised during the on-device AI-vision test, 2026-06-17.
**Next step:** brainstorming → spec → plan → build.

## Gap
After logging a meal by **voice**, the app immediately offers the post-meal symptom/wellbeing follow-up ("how are you feeling?"). After logging by **text** or **photo**, it does **not** — you only get the delayed post-meal notification (if enabled), never the immediate in-flow prompt. The user wants the feeling follow-up offered consistently across all three entry methods.

## What already exists (so this is wiring, not new infra)
- `LogEntryScreen` has an `isFollowUp` mode — text input with hint *"How are you feeling? Rate any discomfort 1–10..."* (`lib/features/logging/screens/log_entry_screen.dart`).
- The voice flow drives it via `VoiceStatus.awaitingFollowUp` + `voiceProvider.primeForSymptomFollowUp(mealId:)` after a meal log (`lib/features/voice/...`).
- Post-meal follow-up **notification** preference exists (`notification_preferences.post_meal_enabled` / `post_meal_delay_minutes`).
- Symptoms/wellbeing logging endpoints already exist (Spec 03), linkable to the meal via `meal_id`.

## Decided direction (to confirm in brainstorming)
After a **text** or **photo** meal log completes, offer the same follow-up the voice path does — i.e. transition the just-logged meal into the `isFollowUp` prompt (text-first), carrying the new `mealId`, so the user can record how they feel right away. Voice remains one input option within that follow-up, not a prerequisite.

## Open questions for brainstorming
- **Immediate vs deferred:** prompt right after logging, only via the existing delayed notification, or both (offer now + still schedule the notification)?
- **Skippable / non-blocking:** the follow-up must be dismissible (logging is already saved); don't gate meal logging on answering.
- **Photo path specifically:** the photo flow ends on the result/review screen (`features/photos/`); where does the follow-up attach — after the foods are confirmed into the meal?
- **Reuse:** route text/photo completion into the existing `LogEntryScreen(isFollowUp: true)` + `primeForSymptomFollowUp(mealId:)` path rather than building a parallel one.
- Relationship to daily-checkin and the post-meal notification (avoid double-prompting).

## Dependencies
- None blocking — the follow-up screen, symptom/wellbeing logging, and meal_id linkage all already exist. This is primarily Flutter wiring on the text/photo completion paths.
