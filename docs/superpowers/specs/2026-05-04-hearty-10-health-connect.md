# Hearty — Sub-Spec 10: Health Connect Integration

**Version:** 1.0  
**Date:** 2026-05-04  
**Status:** Future Phase (Android; plan schema now, implement after Phase 2)  
**Depends on:** Phase 2 (Flutter Android), Phase 4 (AI Intelligence / correlation engine)

---

## 1. Overview

Android Health Connect (formerly part of Google Fit, now a standalone system service) is Android's unified health data hub. Apps like Samsung Health, Fitbit, Garmin Connect, and Google Fit all read and write to Health Connect, making it a rich cross-app data layer available without additional user setup on modern Android devices.

**What Hearty gains from Health Connect:**

- **Richer correlation analysis:** Sleep quality, exercise intensity, and resting heart rate become variables in the AI's pattern detection — not just food and symptoms
- **Write-back:** Hearty's nutrition logs appear in Health Connect so other health apps see what the user ate
- **No duplicate tracking:** Users who already track steps or sleep in another app don't need to re-enter that data in Hearty

**Relationship to Phase 4 (AI Intelligence):** Health Connect data enriches the same correlation engine that links foods to symptoms. This phase should be planned in parallel with Phase 4 even if implemented afterward.

**iOS equivalent:** Apple HealthKit. The `health` Flutter package supports both Health Connect and HealthKit with a unified API. iOS HealthKit integration is a separate decision to make during the iOS phase (Sub-Spec 09).

---

## 2. Read Data Types

Hearty requests read access only for data types that meaningfully improve analysis. Each type must be justified to the user at permission request time.

| Data Type | Health Connect Record Type | User-Facing Justification |
|---|---|---|
| Sleep sessions | `SleepSessionRecord` | "Sleep duration affects digestion and symptom severity" |
| Steps | `StepsRecord` | "Activity level correlates with energy and GI symptoms for some people" |
| Heart rate | `HeartRateRecord` | "Resting heart rate can indicate inflammation or stress response" |
| Exercise sessions | `ExerciseSessionRecord` | "Exercise type and intensity can trigger or reduce symptoms" |
| Body weight | `WeightRecord` | Optional; "Track weight alongside diet changes over time" |

**Not requested at launch (consider later):**
- Blood glucose (relevant for diabetics; adds complexity)
- Menstrual cycle data (high privacy sensitivity; defer)
- Blood pressure (limited correlation value without medical context)

---

## 3. Write Data Types

Hearty writes nutrition data back to Health Connect so other apps and the Health Connect dashboard reflect logged meals.

| Data Type | Health Connect Record Type | Notes |
|---|---|---|
| Nutrition (per meal) | `NutritionRecord` | Calories, macros, meal name; only written when nutrition data is available |

**Write behavior:**
- Write occurs when a meal is logged and nutritional data has been resolved (not when `data_source: "unknown"`)
- Failed writes are queued and retried on next sync; do not block meal logging
- User can disable write-back independently of read access (separate toggle in Settings)

---

## 4. Permission Model

Health Connect uses a granular, per-record-type permission system. Each data type requires its own permission declaration and runtime grant.

**Principles:**
- Request only what is needed for currently implemented features
- Request permissions lazily (at the moment the feature is first used, not on app launch)
- Explain the benefit before showing the permission dialog
- Every Health Connect data type is individually toggleable in Hearty's Settings > Integrations

**Permission request flow:**
1. User navigates to Settings > Integrations > Health Connect (or feature prompt appears in-context)
2. Hearty shows a brief explanation screen: what data will be read, why it improves analysis
3. System Health Connect permission dialog appears (Android handles the UI)
4. Granted permissions are stored in user preferences; denied permissions are noted but not re-requested automatically

**Required `AndroidManifest.xml` entries:**
```xml
<uses-permission android:name="android.permission.health.READ_SLEEP" />
<uses-permission android:name="android.permission.health.READ_STEPS" />
<uses-permission android:name="android.permission.health.READ_HEART_RATE" />
<uses-permission android:name="android.permission.health.READ_EXERCISE" />
<uses-permission android:name="android.permission.health.WRITE_NUTRITION" />
<!-- Add READ_WEIGHT only if weight tracking is included at launch -->
```

**Required `health_permissions` intent filter** in `AndroidManifest.xml` (required by Health Connect for apps that read health data):
```xml
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

---

## 5. Enriched Analysis Examples

These are examples of the kind of AI-generated insights Health Connect data enables. They illustrate the value to users and the expected output of the combined correlation engine.

> "Your bloating symptoms were 40% more severe on nights when you slept under 6 hours compared to nights with 7+ hours, regardless of what you ate."

> "Acid reflux appeared 3 times more frequently in the 4 hours following high-intensity workouts. Lower-intensity activity showed no correlation."

> "Your energy levels on days you logged lunch were notably higher than days without a logged midday meal — even when calorie intake was similar."

> "On your 5 highest-symptom days this month, 4 were preceded by fewer than 5,000 steps. This may reflect sedentary days correlating with GI issues, or vice versa."

These insights are generated by the Phase 4 AI Intelligence layer. Health Connect data is input — it does not independently generate insights without the correlation engine.

---

## 6. Implementation Notes

### 6.1 SDK and Flutter Package

- **Android SDK:** `androidx.health.connect:connect-client` (Jetpack library)
- **Flutter package:** `health` (pub.dev) — supports Health Connect on Android and HealthKit on iOS with a unified Dart API. Evaluate current version and maintenance status at implementation time.
- **Minimum Android version:** Health Connect requires Android 9 (API 28) minimum; some features require Android 14+ for the new permission model

### 6.2 Sync Strategy

- **On app open:** Pull last 24 hours of health data for each granted data type
- **Incremental sync:** Store a `last_health_sync_at` timestamp per data type in Supabase; on subsequent opens, pull only records after that timestamp
- **Write after meal logging:** Attempt Health Connect nutrition write immediately after a meal is saved; queue on failure
- **Background sync:** Not required at launch. Pull-on-open is sufficient for correlation analysis. Revisit if real-time correlation becomes a feature.

### 6.3 Data Storage

Health Connect data pulled by Hearty is stored in Supabase in a `health_metrics` table (or equivalent). It is treated as supplementary context for AI analysis, not the primary record (Health Connect remains the source of truth for this data).

**Proposed schema approach (design now, implement in this phase):**
```sql
-- Add to Phase 1 schema as nullable columns / separate table
-- health_metrics table example:
create table health_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  recorded_at timestamptz not null,
  metric_type text not null,  -- 'sleep_duration', 'steps', 'heart_rate_resting', 'exercise_session', 'weight'
  value_numeric numeric,      -- duration in minutes, step count, bpm, kg
  value_json jsonb,           -- for complex records like exercise sessions
  source text,                -- 'health_connect', 'apple_health', 'manual'
  created_at timestamptz default now()
);
```

**Phase 1 action:** Add `health_metrics` table to the schema with nullable design — no data yet, but the table exists so Phase 4 correlation queries can reference it without a migration surprise.

---

## 7. Privacy

Health data carries elevated sensitivity. Hearty's handling must be explicit and auditable.

**Principles:**
- Health Connect data is pulled to Hearty's servers only when the user has explicitly granted sync permission for that data type
- Users can revoke Health Connect permissions at any time via Android Settings > Health Connect (system UI) or Hearty's Settings > Integrations toggle
- Revoking Health Connect access in Hearty stops future syncs immediately
- Users can delete all Health Connect-derived data from Hearty (Settings > Data > Delete Health Connect Data) without affecting data stored in Health Connect itself
- Hearty never re-exports Health Connect data to third parties
- Health Connect data is stored under the same RLS policy as all other Hearty data (`auth.uid() = user_id`)

**In-app disclosure (required before first permission request):**
> "Hearty will read [data types] from Health Connect to improve pattern analysis. This data is stored on Hearty's servers alongside your food and symptom logs. You can delete it or disconnect at any time in Settings."

---

## 8. Key Open Decisions for This Phase

1. **Which data types to include at launch** — start with sleep + steps only, or include exercise and heart rate from day one? Fewer permissions = higher grant rate.
2. **Whether to include body weight** — useful for some users, may feel intrusive for others; consider making it opt-in within the integration settings.
3. **Evaluate `health` package** — confirm it is actively maintained and supports the latest Health Connect permission model at implementation time.
4. **iOS HealthKit scope** — decide whether HealthKit integration ships with the iOS port (Sub-Spec 09) or as a separate phase.
5. **Correlation engine readiness** — this phase is most valuable when Phase 4 AI Intelligence is complete; decide whether to implement Health Connect data collection before or after Phase 4.
