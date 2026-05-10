DEVICE_ID ?= ZY22KKLSX6
FLUTTER    := /home/evan/tools/flutter/bin/flutter
DEFINES    := --dart-define-from-file=../.env

ADB := /home/evan/tools/android-sdk/platform-tools/adb

.PHONY: run build logs stop api tunnel

tunnel:
	$(ADB) reverse tcp:8080 tcp:8080

run: tunnel
	cd hearty_app && $(FLUTTER) run --device-id $(DEVICE_ID) $(DEFINES)

build:
	cd hearty_app && $(FLUTTER) build apk $(DEFINES)

logs:
	$(ADB) logcat -s flutter:D HeartyWakeWord:D AndroidRuntime:E

stop:
	$(ADB) shell am force-stop com.hearty.app

api:
	cd hearty-api && set -a && . ../.env && set +a && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080
