#!/usr/bin/env bash
set -euo pipefail

LOG=koreader.log
TIMEOUT=15

squashfs-root/AppRun > "$LOG" 2>&1 &
KO_PID=$!

echo "Waiting for KOReader to initialize (PID $KO_PID)..."
for i in $(seq 1 $((TIMEOUT * 2))); do
  sleep 0.5
  if grep -q "Restoring user input handling" "$LOG" 2>/dev/null; then
    echo "KOReader initialized successfully."
    break
  fi
  if ! kill -0 "$KO_PID" 2>/dev/null; then
    echo "KOReader exited prematurely." >&2
    cat "$LOG"
    exit 1
  fi
done

kill "$KO_PID" 2>/dev/null || true
wait "$KO_PID" 2>/dev/null || true
cat "$LOG"

if ! grep -q "Restoring user input handling" "$LOG"; then
  echo "ERROR: KOReader never reached ready state." >&2
  exit 1
fi

if grep -qE " ERROR | WARN.*Patching failed" "$LOG"; then
  echo "ERROR: Patch failure detected in log." >&2
  exit 1
fi

echo "Smoke test passed."