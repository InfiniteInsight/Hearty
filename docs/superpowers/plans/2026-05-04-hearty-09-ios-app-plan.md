# Hearty — iOS App (Spec 09) — Living Plan

**Spec:** [`hearty-09-ios-app.md`](../specs/2026-05-04-hearty-09-ios-app.md)  
**Roadmap Phase:** Future Phase (begin after Spec 04 Android app is stable)  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

> **FUTURE PHASE — Re-verify before execution.**  
> This plan was written speculatively. Before beginning any phase, confirm that all prerequisite specs are complete and that all technologies named here (Porcupine, `siri_suggestions`, Firebase Flutter SDK, `flutter_launcher_icons`, Siri Shortcuts API) are still current. Package versions and Apple platform policies may have changed significantly since this plan was written.

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🔴 Not Started | Spec 04 complete | Claude (start of every session) |
| 1 | iOS Flutter Target Setup | 🔴 Not Started | Phase 0 | Mixed |
| 2 | Auth & Push Notifications | 🔴 Not Started | Phase 1 | Mixed |
| 3 | Wake Word Removal / Siri Entry Point | 🔴 Not Started | Phase 1 | Claude |
| 4 | Siri Shortcuts Integration | 🔴 Not Started | Phase 3 | Mixed |
| 5 | App Store Submission Prep | 🔴 Not Started | Phases 1–4 | Manual |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify prerequisites are complete, confirm the spec and environment are current, and identify which phase to begin.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty iOS App plan.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

IMPORTANT: This is a future/moonshot spec. Before detailing any tasks, verify
that all prerequisite specs are complete and that the technologies referenced
are still current — versions and APIs may have changed significantly since this
plan was written.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-09-ios-app-plan.md
   - docs/superpowers/specs/2026-05-04-hearty-09-ios-app.md

2. Verify prerequisite specs are complete:
   - Spec 04 (Android app): check its plan file for 🟢 Completed status
   - If Spec 04 is not complete, this plan cannot proceed — report that clearly

3. Check the dev environment:
   - flutter --version  (need a version with iOS support; iOS builds require macOS)
   - xcode-select --print-path  (iOS builds require Xcode; report if not present)
   - git status

4. Re-verify current status of named technologies (look up current docs or changelogs):
   - `siri_suggestions` Flutter package — is it actively maintained?
   - `firebase_messaging` Flutter package — current version and iOS/APNs support
   - `flutter_launcher_icons` — current version
   - `permission_handler` — current version and iOS support
   - Siri Shortcuts / INIntent API — any relevant Apple deprecations since 2026-05-04
   - Porcupine background audio on iOS — confirm still not permitted (policy check)

5. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to platform constraints, permission strings, or Apple App Store guidelines.
   List any conflicts found.

6. Report:
   - Prerequisites: complete or blocked
   - Environment: what is/isn't installed; if macOS/Xcode absent, note it clearly
   - Technology currency: any outdated or deprecated items found
   - Spec alignment: drift found, or "clean"
   - Next action: which phase to proceed with, or what to resolve first

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: iOS Flutter Target Setup

**Status:** 🔴 Not Started  
**Goal:** Configure the existing Flutter project to build and run on an iOS device or simulator, including all required Info.plist permission strings.  
**Depends on:** Phase 0 (prerequisites verified)  
**Type:** Mixed

**Key deliverables:**
- `ios/Runner/Info.plist` updated with `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`
- Background fetch entitlement enabled for silent push notifications
- Flutter app builds successfully for iOS simulator
- Existing Android-specific code guarded with `Platform.isAndroid` checks where needed
- `flutter_launcher_icons` configured and iOS icons generated at all required sizes

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Auth & Push Notifications

**Status:** 🔴 Not Started  
**Goal:** Confirm Supabase Google OAuth and Firebase push notifications work correctly on iOS, including APNs key upload and iOS notification permission flow.  
**Depends on:** Phase 1  
**Type:** Mixed

**Key deliverables:**
- APNs authentication key uploaded to Firebase Console
- `firebase_messaging.requestPermission()` triggered post-onboarding (not on first launch)
- Supabase Google OAuth sign-in verified on iOS device/simulator
- Notification permission flow tested and grant rate confirmed
- Background fetch entitlement verified in Xcode for silent push

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Wake Word Removal / Siri Entry Point

**Status:** 🔴 Not Started  
**Goal:** Remove the Porcupine background service from iOS builds and implement the chosen Siri/Action Button entry point as the iOS equivalent of the Android wake word.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- All Porcupine and `VoiceInteractionService` code wrapped in `Platform.isAndroid` guards — no iOS build errors
- Chosen primary entry point implemented (Siri Shortcut vs Action Button tip — decide at phase start based on Android user feedback)
- `SiriShortcutButton` or equivalent widget added to the iOS home screen
- Deep link URL scheme (`hearty://log/meal`, `hearty://log/symptom`) implemented and functional on iOS
- Entry point decision documented in the deviation log

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Siri Shortcuts Integration

**Status:** 🔴 Not Started  
**Goal:** Implement donated Siri intents so that Siri learns and surfaces "log a meal with Hearty" shortcuts at contextually relevant times.  
**Depends on:** Phase 3  
**Type:** Mixed

**Key deliverables:**
- `INInteraction.donate()` called on each voice-logged meal (via platform channel or maintained Flutter package)
- Supported Siri shortcut phrases verified: "Log a meal with Hearty", "Log my symptoms in Hearty", "How am I feeling?"
- Deep link routing confirmed for Siri-opened app sessions
- `siri_suggestions` (or alternative) package evaluated for maintenance status and adopted or substituted
- Shortcuts appear as Siri suggestions on Lock Screen and Spotlight after repeated use

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 5: App Store Submission Prep

**Status:** 🔴 Not Started  
**Goal:** Complete all App Store Connect requirements, conduct TestFlight beta testing, and submit the app for review.  
**Depends on:** Phases 1–4  
**Type:** Manual

**Key deliverables:**
- Privacy Nutrition Labels filled out accurately in App Store Connect
- App description reviewed against health app guidelines (no diagnostic/medical claims language)
- TestFlight beta test completed with at least one non-developer tester
- Privacy Policy URL and Support URL live and linked in App Store Connect
- App submitted to App Store review

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X — changed X because Y`_

---

## Notes

- **macOS required:** iOS Flutter builds require macOS and Xcode. If the primary dev machine is WSL/Linux, a macOS machine or CI runner (e.g., GitHub Actions macOS runner) is needed before any build work can start.
- **HealthKit:** The spec explicitly defers iOS HealthKit integration. Do not implement HealthKit during this phase; coordinate with Spec 10 (Health Connect) which covers the cross-platform `health` package decision.
- **Android deep link alignment:** The `hearty://` URL scheme should be aligned with the Android implementation during Phase 3 so the iOS port is drop-in.
