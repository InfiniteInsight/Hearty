#!/usr/bin/env bash
# Wake word diagnostic — walks through timed recording rounds

ADB=/home/evan/tools/android-sdk/platform-tools/adb
ROUNDS=3
RECORD_SECS=20
TMPDIR=$(mktemp -d /tmp/wakeword_XXXX)

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo ""
echo "══════════════════════════════════════════════════"
echo "  Hey Jarvis — Wake Word Diagnostic"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Rounds    : $ROUNDS"
echo "  Time each : ${RECORD_SECS}s (~5 utterances)"
echo "  Filter    : HeartyWakeWord:D"
echo ""

# Check device is connected
if ! $ADB devices | grep -q "device$"; then
    echo "ERROR: No Android device found. Check USB connection."
    exit 1
fi

# Clear logcat buffer
$ADB logcat -c
echo "  Log buffer cleared."
echo ""

for ((ROUND=1; ROUND<=ROUNDS; ROUND++)); do
    echo "──────────────────────────────────────────────────"
    echo "  Round $ROUND of $ROUNDS"
    echo "──────────────────────────────────────────────────"
    echo ""
    echo "  Press ENTER when ready, then say 'Hey Jarvis'"
    echo "  clearly 5 times at normal speaking volume."
    echo ""
    read -r

    LOGFILE="$TMPDIR/round${ROUND}.log"
    $ADB logcat -c
    $ADB logcat -s HeartyWakeWord:D > "$LOGFILE" &
    LOGCAT_PID=$!

    echo "  🎙  Recording — say 'Hey Jarvis' now!"
    echo ""

    REMAINING=$RECORD_SECS
    while (( REMAINING > 0 )); do
        printf "  %2ds remaining...\r" "$REMAINING"
        sleep 1
        (( REMAINING-- ))
    done
    echo ""

    kill $LOGCAT_PID 2>/dev/null
    wait $LOGCAT_PID 2>/dev/null

    echo ""
    echo "  Results:"

    SCORE_LINES=$(grep -E "score=|WAKE WORD" "$LOGFILE" 2>/dev/null)
    if [[ -z "$SCORE_LINES" ]]; then
        echo "    (no log lines captured — is the wake word service running?)"
    else
        # Show all matching lines, indented
        echo "$SCORE_LINES" | sed 's/^/    /'
    fi

    # Max score this round
    MAX=$(grep "score=" "$LOGFILE" 2>/dev/null \
        | grep -oP 'score=\K[0-9.]+' \
        | sort -n | tail -1)
    echo ""
    [[ -n "$MAX" ]] && echo "  Peak score this round: $MAX" || echo "  Peak score this round: (none)"
    echo ""
done

echo "══════════════════════════════════════════════════"
echo "  SUMMARY — peak scores per round"
echo "══════════════════════════════════════════════════"
echo ""
for ((ROUND=1; ROUND<=ROUNDS; ROUND++)); do
    LOGFILE="$TMPDIR/round${ROUND}.log"
    MAX=$(grep "score=" "$LOGFILE" 2>/dev/null \
        | grep -oP 'score=\K[0-9.]+' \
        | sort -n | tail -1)
    FIRED=$(grep -c "WAKE WORD DETECTED" "$LOGFILE" 2>/dev/null || echo 0)
    printf "  Round %d  peak=%-8s  detections=%s\n" "$ROUND" "${MAX:-(none)}" "$FIRED"
done

echo ""
echo "  Threshold is currently 0.5"
echo ""
echo "  • Scores near zero  → mel scaling or transform bug"
echo "  • Scores 0.1–0.4    → partial detection; may need more utterances to prime buffer"
echo "  • Scores ≥ 0.5      → should fire"
echo ""
