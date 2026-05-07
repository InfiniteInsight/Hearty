# Hearty App

Flutter Android client for the Hearty food and symptom journal.

## Build Configuration (`--dart-define` variables)

All sensitive configuration is passed at build/run time via `--dart-define`. Do **not** commit actual values to version control.

| Variable | Description |
|---|---|
| `API_BASE_URL` | FastAPI base URL (e.g. `https://api.hearty.example.com`) |
| `SUPABASE_URL` | Supabase project URL (e.g. `https://xyzabc.supabase.co`) |
| `SUPABASE_ANON_KEY` | Supabase anon key (public — safe to include in client) |
| `PICOVOICE_ACCESS_KEY` | Picovoice console access key for wake-word detection |
| `FIREBASE_ENABLED` | `true` or `false` — set to `false` to disable FCM in local dev builds |

## Sample `flutter run` command

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.hearty.example.com \
  --dart-define=SUPABASE_URL=https://xyzabc.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here \
  --dart-define=PICOVOICE_ACCESS_KEY=your-picovoice-key-here \
  --dart-define=FIREBASE_ENABLED=false
```

## Accessing `--dart-define` values in Dart

```dart
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const picovoiceAccessKey = String.fromEnvironment('PICOVOICE_ACCESS_KEY');
const firebaseEnabled = String.fromEnvironment('FIREBASE_ENABLED', defaultValue: 'true') == 'true';
```

## Project structure

```
lib/
  app/                  # App-level setup (router, theme, providers)
  features/
    wake_word/          # Picovoice wake-word detection
    voice/              # Speech-to-text voice logging
    logging/            # Manual food/symptom entry
    history/            # Past entries list/detail
    trends/             # Charts and analytics
    health_profile/     # User health data (allergies, conditions)
    settings/           # App settings
    photos/             # Food photo capture
  core/
    api/                # Dio HTTP client, interceptors
    offline/            # Drift local database
    auth/               # Supabase auth helpers
    notifications/      # FCM + local notifications
    sync/               # Offline-to-online sync logic
```
