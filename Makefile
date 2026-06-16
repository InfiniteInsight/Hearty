DEVICE_ID ?= 0B161JEC205801
WIFI_IP    ?= 192.168.0.175
FLUTTER    := /home/evan/tools/flutter/bin/flutter
DEFINES    := --dart-define-from-file=../.env

ADB := /home/evan/tools/android-sdk/platform-tools/adb

.PHONY: run build logs stop api tunnel wifi wifi-port

tunnel:
	pkill -9 -x adb 2>/dev/null; sleep 1; true
	$(ADB) connect $(DEVICE_ID) 2>/dev/null || true
	$(ADB) -s $(DEVICE_ID) reverse tcp:8080 tcp:8080

run: tunnel
	(cd hearty-api && set -a && . ../.env && set +a && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080) & \
	API_PID=$$!; \
	trap "kill $$API_PID 2>/dev/null" EXIT INT TERM; \
	sleep 2; \
	(cd hearty_app && $(FLUTTER) run --device-id $(DEVICE_ID) $(DEFINES))

build:
	cd hearty_app && $(FLUTTER) build apk $(DEFINES)

logs:
	$(ADB) logcat -s flutter:D HeartyWakeWord:D AndroidRuntime:E

stop:
	$(ADB) shell am force-stop com.hearty.app

api:
	cd hearty-api && set -a && . ../.env && set +a && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080

# Run ONCE per phone boot to pin the wireless port to 5555. After this,
# use: make run DEVICE_ID=$(WIFI_IP):5555
# Tries :5555 first (already pinned); else discovers the current
# wireless-debugging port via mdns, pins it with `adb tcpip 5555`, reconnects.
wifi:
	@if $(ADB) connect $(WIFI_IP):5555 >/dev/null 2>&1 && $(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1; then \
	  echo "Already pinned at $(WIFI_IP):5555"; \
	else \
	  echo "Not on :5555 — discovering current wireless-debugging port via mdns..."; \
	  port=$$($(ADB) mdns services 2>/dev/null | grep '_adb-tls-connect' | grep -oE '$(WIFI_IP):[0-9]+' | head -1 | cut -d: -f2); \
	  if [ -n "$$port" ]; then \
	    echo "Found connect port $$port — pinning to 5555..."; \
	    $(ADB) connect $(WIFI_IP):$$port >/dev/null 2>&1; \
	    $(ADB) -s $(WIFI_IP):$$port tcpip 5555 >/dev/null 2>&1; \
	    sleep 3; \
	    $(ADB) connect $(WIFI_IP):5555 >/dev/null 2>&1; \
	  else \
	    echo "No mdns service found (flaky in WSL2). Open the phone's Wireless debugging"; \
	    echo "screen, read the 'IP address & Port', then run:  make wifi-port PORT=<that_port>"; \
	  fi; \
	fi
	@$(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1 \
	  && echo "READY -> make run DEVICE_ID=$(WIFI_IP):5555" \
	  || echo "Not connected. Is the phone awake + on wifi at $(WIFI_IP)? (See message above.)"

# Manual fallback when mdns can't find the port: pass the connect port shown on
# the phone's Wireless debugging screen.  Usage: make wifi-port PORT=39055
wifi-port:
	@test -n "$(PORT)" || { echo "Usage: make wifi-port PORT=<connect_port_from_phone>"; exit 1; }
	$(ADB) connect $(WIFI_IP):$(PORT)
	$(ADB) -s $(WIFI_IP):$(PORT) tcpip 5555
	sleep 3
	$(ADB) connect $(WIFI_IP):5555
	@$(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1 \
	  && echo "READY -> make run DEVICE_ID=$(WIFI_IP):5555" \
	  || echo "Failed to pin 5555 — check the phone is awake on wifi."
