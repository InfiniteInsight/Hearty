# Hearty — Sub-Spec 09: iOS App

**Version:** 1.0  
**Date:** 2026-05-04  
**Status:** Future Phase (begin after Phase 2 Android is stable)  
**Depends on:** Phase 2 (Flutter Android), App Store Developer Account

---

## 1. Overview

Hearty targets iOS using the same Flutter codebase built for Android in Phase 2. The goal is not a rewrite — it is a platform delta: swap or remove Android-specific integrations, satisfy App Store requirements, and ship. The core UX, AI logic, API calls, and Supabase integration are unchanged.

**What changes for iOS:**
- Wake word detection (Porcupine background service not allowed → Siri Shortcuts)
- Push notification stack (FCM still works via Firebase Flutter SDK; APNs is the underlying transport and is handled automatically)
- Permission dialogs use iOS-specific phrasing
- App Store submission process differs from Play Store (review time, privacy labels, health app guidelines)

**What does not change:**
- Supabase Auth (Google OAuth works on iOS via `supabase_flutter`)
- FastAPI and MCP Server integration
- All AI logic and Claude API calls
- Offline queue / sync strategy
- Notification scheduling logic (the Firebase SDK abstracts FCM/APNs)

---

## 2. Platform Differences from Android

### 2.1 Wake Word

**Android approach (Phase 2):** Porcupine wake word runs as a foreground service, always listening for "Hey Hearty."

**iOS constraint:** iOS does not permit always-on background audio processing from third-party apps. Porcupine background services are not available.

**iOS alternatives (pick one or both at ship time):**

| Option | User Experience | Implementation Effort |
|---|---|---|
| Siri Shortcut — "Hey Siri, open Hearty" | Familiar, zero-install friction | Low — Siri opens app; no custom intent needed |
| Siri Shortcut — donated intent ("log a meal") | Opens app directly in voice logging mode | Medium — donate `INIntent` via `app_links` or native channel |
| Action Button (iPhone 15 Pro+) | Single hardware press launches Hearty | Low — user configures in iOS Settings |
| Lock Screen widget shortcut | Tap widget → open Hearty mic screen | Low — Flutter home widget package |

**Decision deferred to iOS phase:** Choose primary entry point based on user testing feedback from Android. Likely answer: Siri Shortcut as default + Action Button as a documented tip for Pro users.

### 2.2 Default Assistant

iOS locks the default voice assistant role to Siri. Hearty cannot intercept "Hey Siri" queries or replace Siri system-wide. The Android "configured default assistant" concept does not apply on iOS.

**Best available approach:**
- Home screen widget → one tap to Hearty mic
- Action Button configuration (iPhone 15 Pro+)
- Lock Screen shortcut
- Donated Siri intents for pattern learning ("Hey Siri, log a meal with Hearty")

The non-health query handoff behavior (routing to the user's configured assistant) is Android-only. On iOS, Hearty simply handles health-adjacent queries; other queries are outside scope.

### 2.3 Push Notifications

Firebase Flutter SDK (`firebase_messaging`) handles both FCM (Android) and APNs (iOS) transparently. The notification scheduling and content logic in FastAPI does not change.

**iOS-specific setup required:**
- APNs authentication key uploaded to Firebase Console (one-time)
- `UNUserNotificationCenter` permission prompt (iOS requires explicit permission request on first launch — Flutter's `firebase_messaging` package handles this)
- Background fetch entitlement enabled in Xcode for silent push notifications

### 2.4 App Store Review Considerations

- Review turnaround: typically 1–3 days (vs Play Store's hours)
- Health app guidelines apply: no medical claims, no diagnostic language
- Privacy Nutrition Labels required at submission (see Section 5)
- TestFlight required for beta distribution (vs Play Store internal testing)

---

## 3. Flutter Adaptations Needed

### 3.1 Wake Word Service — Remove or Stub on iOS

**Phase 2 Android implementation:** A `VoiceInteractionService` and Porcupine integration runs as a foreground service.

**iOS action:**
- Wrap all Porcupine and `VoiceInteractionService` code in `Platform.isAndroid` guards
- On iOS, replace with a `SiriShortcutButton` widget on the home screen
- Remove Android-specific background service lifecycle code from iOS builds

```dart
// Pattern for platform-gating
if (Platform.isAndroid) {
  await WakeWordService.initialize();
}
```

### 3.2 Camera Permissions

Android uses `android.permission.CAMERA`. iOS requires a `NSCameraUsageDescription` string in `Info.plist` explaining WHY the camera is needed. The `permission_handler` Flutter package handles the request; the description string must be added.

**Required `Info.plist` key:**
```
NSCameraUsageDescription: "Hearty uses your camera to photograph meals for automatic food identification."
```

Also required if accessing photo library:
```
NSPhotoLibraryUsageDescription: "Hearty accesses your photo library so you can attach meal photos from your camera roll."
```

### 3.3 Notification Permission Flow

On Android (Phase 2), notification permission is requested as part of FCM setup. On iOS, the system presents a native permission dialog. The `firebase_messaging` package's `requestPermission()` call triggers this on iOS. The flow is the same in Dart code; the dialog appearance differs.

**Recommendation:** Request notification permission after the user completes onboarding (post-first-meal-log), not on first launch. This matches iOS UX conventions and improves grant rates.

### 3.4 Microphone Permissions

```
NSMicrophoneUsageDescription: "Hearty uses your microphone so you can log meals and symptoms by voice."
```

### 3.5 Health App Integration

If Health Connect (Android, Sub-Spec 10) is implemented first, iOS equivalent is Apple HealthKit. The `health` Flutter package supports both. This is an additional future phase decision — do not implement HealthKit during iOS port unless explicitly planned.

---

## 4. Siri Shortcuts Integration

### 4.1 Donated Intents

Siri learns user patterns from donated `INIntent` objects. Each time a user logs a meal via voice in Hearty, donate an intent so Siri can suggest "Log a meal with Hearty" at relevant times (e.g., after breakfast, lunchtime).

**Flutter approach:** Use a native Swift/Obj-C platform channel to call `INInteraction.donate()`, or use a package like `siri_suggestions` (evaluate at implementation time for current maintenance status).

### 4.2 Shortcut Phrases to Support

| Phrase | Behavior |
|---|---|
| "Hey Siri, log a meal with Hearty" | Opens Hearty in voice logging mode |
| "Hey Siri, open Hearty" | Opens Hearty home screen |
| "Hey Siri, how am I feeling?" | Opens symptom logging screen |
| "Hey Siri, log my symptoms in Hearty" | Opens symptom logging screen |

### 4.3 Implementation Notes

- Custom Siri Shortcuts (via `INShortcut` + `INVoiceShortcutCenter`) let users add phrases in Settings > Siri
- Donated intents appear as Siri suggestions on Lock Screen and Spotlight
- Deep link URL scheme (`hearty://log/meal`, `hearty://log/symptom`) handles routing when Siri opens the app
- The same URL scheme should be implemented for Android deep links; align the scheme in Phase 2 so iOS port is drop-in

---

## 5. App Store Submission Checklist

### 5.1 Privacy Nutrition Labels

Apple requires disclosure of all data collected. Based on Hearty's data model:

| Data Type | Collected | Used | Linked to User |
|---|---|---|---|
| Health & Fitness — Other | Yes (meals, symptoms) | Yes (core app function) | Yes |
| Identifiers — User ID | Yes (Supabase UUID) | Yes | Yes |
| Usage Data — App launches | Via Firebase Analytics | Yes | No (aggregated) |
| Contact Info — Email | Yes (magic link / account) | Yes | Yes |
| Photos or Videos | Yes (meal photos) | Yes (food identification) | Yes |

**Decision at submission time:** Audit the exact Firebase Analytics events collected. If analytics are not implemented, remove that row.

### 5.2 Health App Guidelines Compliance

- No language suggesting Hearty diagnoses, treats, or prevents any medical condition
- App description must not claim medical professional endorsement
- "Pattern observations, not medical advice" language should appear in onboarding and Settings > About
- If claiming Health & Fitness category: primary function must be tracking, not therapy or treatment

### 5.3 App Description

**Avoid in App Store copy:**
- "diagnose", "treat", "cure", "medical advice", "clinically proven"
- Implied claims about specific condition treatment (e.g., "cures IBS")

**Safe framing:**
- "helps you notice patterns between what you eat and how you feel"
- "personal food and symptom journal"
- "spot potential food sensitivities over time"

### 5.4 Additional Checklist Items

- [ ] Apple Developer Program membership active ($99/year)
- [ ] App icons provided at all required sizes (use Flutter's `flutter_launcher_icons` package)
- [ ] Launch screen / splash screen configured for iOS
- [ ] TestFlight beta test completed with at least one non-developer tester
- [ ] Privacy Policy URL live and linked in App Store Connect
- [ ] Support URL live and linked in App Store Connect
- [ ] Age rating set (likely 4+ or 12+ depending on content review)
- [ ] Export compliance: Hearty uses standard HTTPS encryption; answer "yes" to standard encryption exemption

---

## 6. Timeline

**Prerequisites:** Phase 2 Android app is stable and in production use.

**Estimated delta from Android:**

| Work Item | Estimated Effort |
|---|---|
| Wake word removal / Siri Shortcuts | 2–3 days |
| iOS permission strings + Info.plist | 0.5 days |
| APNs setup in Firebase Console | 0.5 days |
| Notification permission flow iOS tuning | 1 day |
| App icon + launch screen assets | 1 day |
| TestFlight setup and beta testing | 1–2 weeks calendar time |
| App Store submission and review | 1–3 days calendar time |
| **Total active dev time** | **~1 week** |

**Key open decisions to make when this phase starts:**
1. Which Siri entry point to lead with (Siri Shortcut vs Action Button tip)
2. Whether to implement donated intents at launch or post-launch
3. Whether to gate HealthKit integration into this phase or keep it separate
4. Confirm current maintenance status of any Siri/shortcut Flutter packages before adopting
