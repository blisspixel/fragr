#!/usr/bin/env bash
# Photograph Level 17's gallery fight as a carried campaign run: the player
# arrives with the kit, health and continues earned through Episode IV (a
# validated M16 departure from the server's own run-file tests), resumed in
# the durable local child, not a fresh fists-only development party.
# Usage: tools/qa_m17_carried.sh [output directory] (other qa_tour settings
# pass through the environment).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/.agents/qa/m17-carried-$(date -u +%Y%m%d-%H%M%S)}"
mkdir -p "$ROOT/.agents"
fixture=$(mktemp -d "$ROOT/.agents/m17-carry-XXXXXXXX")
rmdir "$fixture"
LOCALEXCEPTION_TEST_RUN_FIXTURE_DIR="$fixture" cargo test -p localexception-server --lib --locked \
  m16_departure_fixture_carries_an_earned_kit_into_m17 >"$ROOT/.agents/m17-carry-fixture.log" 2>&1 || {
  cat "$ROOT/.agents/m17-carry-fixture.log"
  echo "qa_m17_carried: fixture test failed" >&2
  exit 1
}
[ -f "$fixture/run.json" ] || { echo "qa_m17_carried: no fixture written" >&2; exit 1; }
LOCALEXCEPTION_QA_LOCAL_MISSION=peace_without_interruption LOCALEXCEPTION_QA_RUN_FIXTURE="$fixture" \
  LOCALEXCEPTION_QA_MANIFEST="${LOCALEXCEPTION_QA_MANIFEST:-res://qa/m17-gallery-fight.json}" \
  bash "$ROOT/tools/qa_tour.sh" "$OUT_DIR"
status=$?
rm -f "$fixture/run.json" "$fixture/run.lock"
rmdir "$fixture" 2>/dev/null
exit $status
