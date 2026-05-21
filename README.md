# Hearty

Food and symptom journal. Flutter Android client + FastAPI backend.

## Repo layout

```
hearty_app/      Flutter Android app
hearty-api/      FastAPI backend (Python)
hearty-mcp/      MCP server
supabase/        Supabase migrations and config
docs/            Specs and implementation plans
```

## Prerequisites

- **WSL2** (Ubuntu) — all dev work runs here
- **Flutter** at `~/tools/flutter`
- **Android SDK** at `~/tools/android-sdk` (includes `platform-tools/adb`)
- **Python 3** with a venv at `hearty-api/.venv`
- **usbipd-win** installed on Windows (for USB device forwarding to WSL2)
- **`.env`** file at repo root (see [Environment variables](#environment-variables))

## Environment variables

All secrets live in `.env` at the project root. The Makefile loads it automatically — never run `flutter run` directly.

| Variable | Description |
|---|---|
| `API_BASE_URL` | FastAPI base URL used by the app |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon key |
| `PICOVOICE_ACCESS_KEY` | Picovoice console key (wake-word) |
| `FIREBASE_ENABLED` | `true` or `false` |

## One-time setup

1. Create `.env` at the repo root with the variables above.
2. Create the Python venv and install dependencies:
   ```bash
   cd hearty-api
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   ```
3. On Windows, install usbipd-win (if not already present):
   ```powershell
   winget install --interactive --exact dorssel.usbipd-win
   ```

## Daily dev workflow

Every time you plug in the phone or restart WSL, follow these steps in order.

### 1 — Attach the phone to WSL2 (Windows PowerShell, run as Administrator)

```powershell
usbipd list
```

Find your device (e.g. `2-9  18d1:4ee7  Pixel 4a`) and attach it:

```powershell
usbipd attach --wsl --busid 2-9
```

The STATE column should change from `Not shared` to `Attached`.

### 2 — Verify ADB sees the phone (WSL terminal)

```bash
adb kill-server && adb devices
```

Expected output:
```
* daemon started successfully
List of devices attached
0B161JEC205801	device
```

If the list is empty, the USB-IP link didn't stabilize — try step 1 again, then repeat step 2.

### 3 — Start the API (WSL terminal 1)

```bash
make api
```

Starts uvicorn on `0.0.0.0:8080`. Leave this running.

### 4 — Run the app (WSL terminal 2)

```bash
make run
```

This sets up an ADB reverse tunnel (`tcp:8080 → tcp:8080`) so the app can reach the API on your machine, then launches Flutter.

## Make targets

| Target | What it does |
|---|---|
| `make run` | Tunnel + `flutter run` on the connected device |
| `make build` | Build a debug APK |
| `make api` | Start the FastAPI dev server on port 8080 |
| `make tunnel` | Set up the ADB reverse tunnel only |
| `make logs` | Stream Flutter + wake-word logcat output |
| `make stop` | Force-stop the app on device |

## Troubleshooting

### `adb: device 'XXXXX' not found` / `make run` hangs after printing the adb command

ADB lost the USB-IP connection. Fix:
1. Re-attach in Windows: `usbipd attach --wsl --busid <busid>`
2. In WSL: `adb kill-server && adb devices`
3. Retry `make run`

### Device doesn't appear in `usbipd list` Connected section

The phone needs to be physically plugged in and USB debugging must be authorised on the device. Check the phone screen for a "Allow USB debugging?" prompt and tap OK.

### App can't reach the API

- Confirm `make api` is running and shows no startup errors.
- Confirm the ADB reverse tunnel is active (`make tunnel` to re-run it).
- The tunnel maps `device:8080 → host:8080`, so the app's `API_BASE_URL` should use `http://10.0.2.2:8080` for emulator or `http://localhost:8080` via the reverse tunnel on a physical device.

### Slow Gradle build / install (`1000+ seconds`)

This happens when another `make run` is already running in a different terminal and holding the ADB server. Stop the existing session first (`Ctrl-C`), then retry.
