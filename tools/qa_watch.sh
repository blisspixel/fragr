#!/usr/bin/env bash
# Capture one live agent's actual first-person camera and authoritative tick
# evidence. Local rules only, no key and no paid provider calls.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="${1:-$ROOT/.agents/watch/$STAMP}"
mkdir -p "$OUT" || exit 1
OUT="$(cd "$OUT" && pwd)"
PORT="${FRAGR_WATCH_PORT:-6768}"
WATCH_SECONDS="${FRAGR_WATCH_SECONDS:-45}"
WATCH_SEED="${FRAGR_WATCH_SEED:-1}"
if ! [[ "$PORT" =~ ^(0|[1-9][0-9]*)$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "qa_watch: FRAGR_WATCH_PORT must be 1 through 65535" >&2
  exit 1
fi
if ! [[ "$WATCH_SECONDS" =~ ^(0|[1-9][0-9]*)$ ]] || (( WATCH_SECONDS < 1 || WATCH_SECONDS > 3600 )); then
  echo "qa_watch: FRAGR_WATCH_SECONDS must be 1 through 3600" >&2
  exit 1
fi
if ! [[ "$WATCH_SEED" =~ ^(0|[1-9][0-9]*)$ ]] || (( ${#WATCH_SEED} > 20 )); then
  echo "qa_watch: FRAGR_WATCH_SEED must be a nonnegative u64" >&2
  exit 1
fi
NAME="${FRAGR_WATCH_NAME:-WatchAgent-$$}"
if ! [[ "$NAME" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
  echo "qa_watch: FRAGR_WATCH_NAME must be 1 to 32 letters, numbers, _ or -" >&2
  exit 1
fi
SERVER_PID=""
BRAIN_PID=""
GODOT_PID=""
XVFB_PID=""

cleanup() {
  [ -n "$BRAIN_PID" ] && kill "$BRAIN_PID" >/dev/null 2>&1
  [ -n "$GODOT_PID" ] && kill "$GODOT_PID" >/dev/null 2>&1
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" >/dev/null 2>&1
  [ -n "$XVFB_PID" ] && kill "$XVFB_PID" >/dev/null 2>&1
  [ -n "$BRAIN_PID" ] && wait "$BRAIN_PID" 2>/dev/null
  [ -n "$GODOT_PID" ] && wait "$GODOT_PID" 2>/dev/null
  [ -n "$SERVER_PID" ] && wait "$SERVER_PID" 2>/dev/null
  [ -n "$XVFB_PID" ] && wait "$XVFB_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT

GODOT_BIN="${FRAGR_GODOT:-${GODOT_BIN:-}}"
if [ -z "$GODOT_BIN" ]; then
  for candidate in \
    "/c/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe" \
    "/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"; do
    [ -x "$candidate" ] && GODOT_BIN="$candidate" && break
  done
fi
if [ -z "$GODOT_BIN" ]; then
  GODOT_BIN="$(command -v godot || command -v Godot_v4.7.2-stable_linux.x86_64 || true)"
fi
if [ -z "$GODOT_BIN" ]; then
  echo "qa_watch: Godot 4.7.2 is required; set FRAGR_GODOT" >&2
  exit 1
fi
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  exec 3>&- 3<&-
  echo "qa_watch: port $PORT is already in use" >&2
  exit 1
fi

cargo build -p fragr-server -p fragr-brain --release --locked >"$OUT/build.log" 2>&1 || {
  echo "qa_watch: Rust build failed; see $OUT/build.log" >&2; exit 1; }
"$GODOT_BIN" --path "$ROOT/client" --headless --import >"$OUT/import.log" 2>&1 || {
  echo "qa_watch: Godot import failed; see $OUT/import.log" >&2; exit 1; }
if grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$OUT/import.log"; then
  echo "qa_watch: Godot import reported errors; see $OUT/import.log" >&2
  exit 1
fi

"$ROOT/target/release/fragr-server" --bind "127.0.0.1:$PORT" --bots 0 \
  --map-file server/maps/m01-recall-notice.json --campaign-run \
  --difficulty "${FRAGR_WATCH_DIFFICULTY:-standard}" --seed "$WATCH_SEED" --status-every-s 0 \
  >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
UP=0
for _ in $(seq 1 50); do
  if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    exec 3>&- 3<&-
    if kill -0 "$SERVER_PID" 2>/dev/null &&
       grep -Fq "WebSocket server listening on 127.0.0.1:$PORT" "$OUT/server.log"; then
      UP=1
      break
    fi
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if [ "$UP" -ne 1 ]; then
  echo "qa_watch: owned server did not start; see $OUT/server.log" >&2
  exit 1
fi

if [ "$(uname -s)" = "Linux" ]; then
  command -v Xvfb >/dev/null 2>&1 || {
    echo "qa_watch: Xvfb is required on Linux" >&2; exit 1; }
  DISPLAY_NUM="${FRAGR_WATCH_DISPLAY_NUM:-99}"
  if ! [[ "$DISPLAY_NUM" =~ ^(0|[1-9][0-9]*)$ ]] || (( DISPLAY_NUM > 999 )); then
    echo "qa_watch: FRAGR_WATCH_DISPLAY_NUM must be 0 through 999" >&2
    exit 1
  fi
  Xvfb ":$DISPLAY_NUM" -screen 0 1280x720x24 >"$OUT/xvfb.log" 2>&1 &
  XVFB_PID=$!
  sleep 1
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "qa_watch: owned Xvfb did not start; see $OUT/xvfb.log" >&2
    exit 1
  fi
  DISPLAY=":$DISPLAY_NUM" LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
    FRAGR_SERVER="127.0.0.1:$PORT" FRAGR_WATCH_NAME="$NAME" \
    FRAGR_WATCH_DIR="$OUT" \
    "$GODOT_BIN" --path "$ROOT/client" --rendering-driver opengl3 \
    --windowed --resolution 1280x720 --script res://scripts/qa_watch.gd \
    >"$OUT/watch.log" 2>&1 &
else
  FRAGR_SERVER="127.0.0.1:$PORT" FRAGR_WATCH_NAME="$NAME" \
    FRAGR_WATCH_DIR="$OUT" \
    "$GODOT_BIN" --path "$ROOT/client" --rendering-driver opengl3 \
    --windowed --resolution 1280x720 --script res://scripts/qa_watch.gd \
    >"$OUT/watch.log" 2>&1 &
fi
GODOT_PID=$!
WATCH_READY=0
for _ in $(seq 1 100); do
  if grep -Fq 'Connected to server!' "$OUT/watch.log"; then
    WATCH_READY=1
    break
  fi
  if ! kill -0 "$GODOT_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if [ "$WATCH_READY" -ne 1 ]; then
  echo "qa_watch: spectator did not connect; see $OUT/watch.log" >&2
  exit 1
fi

"$ROOT/target/release/fragr-brain" --provider local play \
  --server "ws://127.0.0.1:$PORT" --name "$NAME" \
  --max-seconds "$WATCH_SECONDS" \
  --timeline-path "$OUT/timeline.json" \
  >"$OUT/brain.log" 2>&1 &
BRAIN_PID=$!

for _ in $(seq 1 200); do
  if ! kill -0 "$GODOT_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if kill -0 "$GODOT_PID" 2>/dev/null; then
  echo "qa_watch: spectator capture timed out; see $OUT/watch.log" >&2
  exit 1
fi
wait "$GODOT_PID"
WATCH_STATUS=$?
GODOT_PID=""
if [ "$WATCH_STATUS" -ne 0 ]; then
  echo "qa_watch: capture failed; see $OUT/watch.log" >&2
  exit "$WATCH_STATUS"
fi
if ! grep -Fq 'qa_watch: PASS ' "$OUT/watch.log" ||
   grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$OUT/watch.log"; then
  echo "qa_watch: capture has errors or no PASS marker; see $OUT/watch.log" >&2
  exit 1
fi
for _ in $(seq 1 $(( (WATCH_SECONDS + 30) * 5 ))); do
  if ! kill -0 "$BRAIN_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if kill -0 "$BRAIN_PID" 2>/dev/null; then
  echo "qa_watch: brain timed out; see $OUT/brain.log" >&2
  exit 1
fi
wait "$BRAIN_PID"
BRAIN_STATUS=$?
BRAIN_PID=""
if [ "$BRAIN_STATUS" -ne 0 ]; then
  echo "qa_watch: brain failed; see $OUT/brain.log" >&2
  exit "$BRAIN_STATUS"
fi
FRAGR_WATCH_DIR="$OUT" FRAGR_WATCH_VERIFY_BRAIN="$OUT/brain.log" \
  "$GODOT_BIN" --path "$ROOT/client" --headless \
  --script res://scripts/qa_watch.gd >"$OUT/verify.log" 2>&1 || {
  echo "qa_watch: receipts do not match; see $OUT/verify.log" >&2
  exit 1
}
if ! grep -Fq 'qa_watch: VERIFIED ' "$OUT/verify.log" ||
   grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$OUT/verify.log"; then
  echo "qa_watch: receipt check has errors or no VERIFIED marker; see $OUT/verify.log" >&2
  exit 1
fi
echo "qa_watch: captured one first-person participant"
echo "qa_watch: frames and manifest in $OUT"
echo "qa_watch: paired receipt in $OUT/verified.json"
