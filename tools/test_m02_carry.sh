#!/usr/bin/env bash
# Exercise the saved M01 departure through M02 death and retry in a real local child.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .agents
fixture=$(mktemp -d "$PWD/.agents/m02-carry-XXXXXXXX")
native_fixture=$fixture
if command -v cygpath >/dev/null 2>&1; then
  native_fixture=$(cygpath -w "$fixture")
fi

FRAGR_TEST_RUN_FIXTURE_DIR="$native_fixture" cargo test -p fragr-server \
  --test local_child --locked isolated_m01_departure_fixture_for_m02_client_smoke -- --exact

godot="${GODOT_BIN:-godot}"
out=$(FRAGR_RUN_DIR="$native_fixture" "$godot" --headless --path client \
  --check-only --script res://qa/run_carry_live.gd 2>&1) || {
  printf '%s\n' "$out"
  echo 'M02 carry check: FAIL (parse)'
  exit 1
}
if grep -qE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' <<<"$out"; then
  printf '%s\n' "$out"
  echo 'M02 carry check: FAIL (parse diagnostic)'
  exit 1
fi

status=0
out=$(FRAGR_RUN_DIR="$native_fixture" "$godot" --headless --path client \
  --script res://qa/run_carry_live.gd 2>&1) || status=$?
if [ "$status" -ne 0 ] || grep -qE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' <<<"$out" ||
   ! grep -qF 'run_carry_live: PASS M01 departure, M02 carry, death, restart and one spent continue' <<<"$out"; then
  printf '%s\n' "$out"
  echo "M02 carry check: FAIL (exit $status)"
  exit 1
fi
echo 'M02 carry check: PASS'
