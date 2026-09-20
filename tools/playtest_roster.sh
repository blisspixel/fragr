#!/usr/bin/env bash
# Mixed network clients across the shipped maps. Keep every failure/report.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
OUT="${1:-.agents/playtest/roster}"
mkdir -p "$OUT" || exit 1
cargo build -p fragr-playtest --release --locked || exit 1
failed=0
while read -r map agents seed; do
  report="$OUT/map${map}-seed${seed}.json"
  log="$OUT/map${map}-seed${seed}.log"
  "$ROOT/target/release/fragr-playtest" --map "$map" --agents "$agents" \
    --seed "$seed" --tiers reflex,planner --rounds 1 --frag-limit 8 \
    --time-limit-seconds 60 --max-seconds 75 --assert --report "$report" >"$log" 2>&1 || failed=1
  cat "$log"
done <<'CASES'
1 2 67
2 6 42
3 6 19
4 8 42
5 12 42
6 16 42
CASES
exit "$failed"
