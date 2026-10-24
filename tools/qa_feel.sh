#!/usr/bin/env bash
# Rendered feel probe: start a bot-free Arena Duel server, run
# client/scripts/qa_feel.gd in a real window against it, and keep feel.json,
# feel.md and the motion strips under the output directory.
#
# Usage: tools/qa_feel.sh [output directory]
# Default output: .agents/feel/<stamp>/ (gitignored). GODOT_BIN names Godot
# 4.7.2. FRAGR_PORT (default 6791) and FRAGR_QA_BOTS (default 0) change the
# server. FRAGR_FEEL_STRIPS=0 skips the strip pass. The window opens on the
# current display; audio uses the Dummy driver.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT_DIR="${1:-$ROOT/.agents/feel/$STAMP}"
PORT="${FRAGR_PORT:-6791}"
BOTS="${FRAGR_QA_BOTS:-0}"
GODOT="${GODOT_BIN:-godot}"

if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "qa_feel: port $PORT is already in use; choose FRAGR_PORT" >&2
  exit 1
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
SERVER="${FRAGR_SERVER_BIN:-$ROOT/target/release/fragr-server}"
if [ ! -x "$SERVER" ]; then
  echo "qa_feel: build the release server first (cargo build -p fragr-server --release --locked)" >&2
  exit 1
fi
"$SERVER" --bind "127.0.0.1:$PORT" --bots "$BOTS" --map "${FRAGR_QA_MAP:-1}" --no-round-events \
  >"$OUT_DIR/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1' EXIT
UP=0
for _ in $(seq 1 50); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
  if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then exec 3>&- 3<&-; UP=1; break; fi
  sleep 0.2
done
if [ "$UP" -ne 1 ]; then
  echo "qa_feel: server never came up on port $PORT" >&2
  exit 1
fi
FRAGR_SERVER="127.0.0.1:$PORT" FRAGR_QA_DIR="$OUT_DIR" FRAGR_RUN_DIR="$OUT_DIR/run" \
  "$GODOT" --path "$ROOT/client" --audio-driver Dummy --windowed --resolution 1280x720 \
  --script res://scripts/qa_feel.gd >"$OUT_DIR/client.log" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ] || grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$OUT_DIR/client.log"; then
  echo "qa_feel: probe failed (exit $STATUS); see $OUT_DIR/client.log" >&2
  exit 1
fi
cat "$OUT_DIR/feel.md"
echo "qa_feel: done. Evidence: $OUT_DIR"
