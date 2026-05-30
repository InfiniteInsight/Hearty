# Conversation Style Setting

## Overview

Add a user-controlled toggle that determines how Hearty's AI responds during all interactions — meal logging, wellbeing check-ins, and post-meal follow-ups. The setting has two modes: **Warm & Empathetic** (current behaviour) and **Concise & Quick** (stripped of commentary, same structured rules). Users choose during onboarding and can change it anytime in Settings.

---

## Data & Storage

### Database

New migration adds a `conversation_style` column to `notification_preferences`:

```sql
ALTER TABLE notification_preferences
  ADD COLUMN conversation_style text NOT NULL DEFAULT 'warm'
  CHECK (conversation_style IN ('warm', 'concise'));
```

Existing users receive `'warm'` as the default, preserving current behaviour with no visible change.

### Pre-login persistence

The onboarding step runs before authentication. The choice is saved to `SharedPreferences` temporarily:

| Key | Type | Values |
|-----|------|--------|
| `conversation_style_configured` | bool | gates whether onboarding step shows |
| `conversation_style` | String | `'warm'` \| `'concise'` |

After login, both `OnboardingScreen._finish()` and `_skipToHome()` read the key and sync it to Supabase alongside the existing notification preferences (matching the exact pattern used for `notification_post_meal_enabled` and `notification_checkin_enabled`).

"Skip for now" writes `conversation_style = 'warm'` and `conversation_style_configured = true`.

### Flutter model

Add `conversationStyle` (String, default `'warm'`) to `UserPreferences`:

- `fromJson`: reads `conversation_style` snake_case field
- `toJson`: writes `conversation_style`
- `copyWith`: includes `conversationStyle`

---

## Backend & API

### Preferences endpoint

`conversation_style` is added to `UserPreferencesSchema` and flows through the existing `GET /api/preferences` and `PUT /api/preferences` endpoints. The upsert to `notification_preferences` includes the new column. No new endpoints are needed.

### Chat endpoint

The chat request body gains a `conversation_style` field (`'warm'` | `'concise'`). The Flutter app reads the value from `preferencesProvider` and includes it in every chat request.

The backend selects between two system prompt variants based on this field.

### System prompt architecture

Both variants share an identical **structural rules block** (one question at a time, clarification criteria, off-topic rejection, meal extraction logic). A **persona/tone block** is prepended and differs between modes:

**Warm** (current behaviour):
- Friendly, supportive tone
- Briefly explains why clarification is needed before asking
- Responds empathetically to reported symptoms and low wellbeing scores
- Confirmations include warmth ("I've noted that down")

**Concise**:
- Terse, functional tone — no commentary on food choices or feelings
- Clarification questions asked bare, without preamble or explanation
- No empathetic remarks on symptoms or wellbeing
- Confirmations are minimal ("Logged.")
- All structural rules (what to clarify, when to ask, format) remain unchanged

Keeping the tone block separate from the structural rules means logic updates only need to happen in one place.

---

## Flutter UI

### New screens

**`ConversationStyleSetupScreen`** (`/conversation-style-setup`)
- Dark background (`Colors.black`), matches `NotificationSetupScreen` exactly
- Header: 💬 emoji, title "How should Hearty talk to you?", subtitle "You can change this anytime in Settings."
- Two selectable cards with example chat snippets (❤️ Warm & Empathetic / ⚡ Concise & Quick)
- "Looks good →" button saves selection and configured flag to SharedPreferences, then pops
- "Skip for now" defaults to `'warm'`, marks configured, pops
- Initial selection: whichever card matches the current SharedPreferences value (or Warm if unset)

**`ConversationStyleScreen`** (`/settings/conversation`)
- Standard light scaffold with AppBar ("Conversation Style")
- Same two selectable cards with example snippets
- "Save" button writes via `preferencesProvider.save()` using the existing pattern
- No "Skip" — user must save or use back

### Onboarding flow

`SetupScreen._runSetup()` gains a third step after the notification preferences step:

```dart
final styleConfigured = prefs.getBool('conversation_style_configured') ?? false;
if (!styleConfigured) {
  await context.push('/conversation-style-setup');
}
```

### Settings screen

`SettingsScreen` gets a new list tile between Voice and Health Profile:

```
Conversation style   →   /settings/conversation
```

### Router

Two new routes added to `router.dart`:

| Path | Name | Screen |
|------|------|--------|
| `/conversation-style-setup` | `conversationStyleSetup` | `ConversationStyleSetupScreen` |
| `/settings/conversation` | `conversationStyle` | `ConversationStyleScreen` |

`/conversation-style-setup` must be excluded from the authentication redirect (same pattern as `/setup` and `/notification-setup`).

### Chat API call

`HeartyApiClient`'s chat method gains a `conversationStyle` parameter. At the call site, the value is read from `preferencesProvider` (defaulting to `'warm'` if preferences haven't loaded yet).

---

## Existing user migration

- Database default of `'warm'` ensures no existing user sees a behaviour change
- SharedPreferences key `conversation_style_configured` is absent for existing users — they skip the onboarding step entirely
- Existing users access the setting via Settings → Conversation style

---

## Out of scope

- More than two modes
- Per-interaction style override
- Style affecting the TTS voice or speech rate
