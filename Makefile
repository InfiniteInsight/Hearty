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
	@echo "[wifi] Phone $(WIFI_IP) — checking reachability (1s ping)..."
	@ping -c1 -W1 $(WIFI_IP) >/dev/null 2>&1 && echo "[wifi]   reachable." \
	  || echo "[wifi]   NOT pinging — phone may be asleep/off-wifi; continuing anyway."
	@echo "[wifi] Trying existing pin at $(WIFI_IP):5555 (max 8s)..."
	@if timeout 8 $(ADB) connect $(WIFI_IP):5555 >/dev/null 2>&1 && $(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1; then \
	  echo "[wifi]   already pinned."; \
	else \
	  echo "[wifi]   not on :5555. Scanning mdns for the current connect port (max 5s)..."; \
	  port=$$(timeout 5 $(ADB) mdns services 2>/dev/null | grep '_adb-tls-connect' | grep -oE '$(WIFI_IP):[0-9]+' | head -1 | cut -d: -f2); \
	  if [ -n "$$port" ]; then \
	    echo "[wifi]   found port $$port — connecting (max 8s)..."; \
	    timeout 8 $(ADB) connect $(WIFI_IP):$$port >/dev/null 2>&1 || true; \
	    echo "[wifi]   issuing 'adb tcpip 5555'..."; \
	    $(ADB) -s $(WIFI_IP):$$port tcpip 5555 >/dev/null 2>&1 || true; \
	    echo "[wifi]   waiting 3s for adbd to restart on 5555..."; \
	    sleep 3; \
	    echo "[wifi]   reconnecting on 5555 (max 8s)..."; \
	    timeout 8 $(ADB) connect $(WIFI_IP):5555 >/dev/null 2>&1 || true; \
	  else \
	    echo "[wifi]   no mdns service found (flaky in WSL2, or phone off-wifi)."; \
	    echo "[wifi]   On the phone: Developer options > Wireless debugging > read 'IP address & Port',"; \
	    echo "[wifi]   then run:  make wifi-port PORT=<that_port>"; \
	  fi; \
	fi
	@echo "[wifi] Verifying 5555..."
	@$(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1 \
	  && echo "[wifi] READY -> make run DEVICE_ID=$(WIFI_IP):5555" \
	  || echo "[wifi] NOT connected. Is the phone awake + on wifi at $(WIFI_IP)? Try: make wifi-port PORT=<port>"

# Manual fallback when mdns can't find the port: pass the connect port shown on
# the phone's Wireless debugging screen.  Usage: make wifi-port PORT=39055
wifi-port:
	@test -n "$(PORT)" || { echo "Usage: make wifi-port PORT=<connect_port_from_phone>"; exit 1; }
	@echo "[wifi-port] Connecting to $(WIFI_IP):$(PORT) (max 8s)..."
	@timeout 8 $(ADB) connect $(WIFI_IP):$(PORT) || true
	@echo "[wifi-port] Issuing 'adb tcpip 5555'..."
	@$(ADB) -s $(WIFI_IP):$(PORT) tcpip 5555 || true
	@echo "[wifi-port] Waiting 3s for adbd to restart on 5555..."
	@sleep 3
	@echo "[wifi-port] Reconnecting on 5555 (max 8s)..."
	@timeout 8 $(ADB) connect $(WIFI_IP):5555 || true
	@$(ADB) -s $(WIFI_IP):5555 get-state >/dev/null 2>&1 \
	  && echo "[wifi-port] READY -> make run DEVICE_ID=$(WIFI_IP):5555" \
	  || echo "[wifi-port] Failed to pin 5555 — check the phone is awake on wifi at $(WIFI_IP)."
