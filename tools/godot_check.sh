#!/usr/bin/env bash
# Headless Godot checks for the client: import the project, parse every script,
# run the harnesses. Godot can exit 0 with errors in its log, so the log lines
# are the verdict. Set GODOT_BIN to a 4.7.2-stable binary, or have `godot` on PATH.
# Shell substitutes can set FRAGR_CHECK_ENGINE_SHELL to their interpreter.
# Build fragr-server --release --locked first; local campaign checks spawn it.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
# Native launch keeps the retained Child handle on the engine or its console
# wrapper. Shell fixtures opt into an interpreter without an emulated exec.
engine=("$GODOT")
if [ -n "${FRAGR_CHECK_ENGINE_SHELL:-}" ]; then
  engine=("$FRAGR_CHECK_ENGINE_SHELL" "$GODOT")
fi
runner="${FRAGR_CHECK_PROCESS_BIN:-$PWD/target/debug/fragr-check-process}"
if [ -z "${FRAGR_CHECK_PROCESS_BIN:-}" ]; then
  cargo build -p fragr-playtest --bin fragr-check-process --locked || exit 1
  if [ -f "$runner.exe" ]; then runner="$runner.exe"; fi
fi
mkdir -p .agents
logs=$(mktemp -d "$PWD/.agents/godot-check-XXXXXX") || exit 1
echo "Godot check logs: $logs"
check_number=0
fail=0

# Godot may print an error and return zero, or fail without a script diagnostic.
# A PASS line cannot cancel an earlier error in the same run.
check() {
  local label="$1" marker="$2" out status log
  shift 2
  check_number=$((check_number + 1))
  log="$logs/$check_number.log"
  echo "BEGIN $label ($log)"
  "$runner" --timeout-ms "${FRAGR_CHECK_TIMEOUT_MS:-180000}" --output "$log" -- \
    "${engine[@]}" --headless --path client "$@"
  status=$?
  out=$(cat "$log" 2>/dev/null)
  echo "END  $label (exit $status)"
  # Engine severity labels are uppercase. Verbose socket diagnostics also say
  # "error", including the intentional child crash in test_local_campaign.
  # Direct input avoids SIGPIPE from early matches under pipefail.
  if [ "$status" -ne 0 ] || grep -qE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' <<<"$out"; then
    echo "FAIL $label (exit $status)"
    printf '%s\n' "$out"
    fail=1
    return 1
  fi
  if [ -n "$marker" ] && ! grep -qF "$marker" <<<"$out"; then
    echo "FAIL $label (missing $marker)"
    printf '%s\n' "$out"
    fail=1
    return 1
  fi
  echo "ok   $label"
}

check version "" --version || { echo "godot binary not found or failed (set GODOT_BIN)"; exit 1; }
# Parsing with a failed import only produces secondary missing-resource errors.
check import "" --import || { echo "Godot checks: FAIL (import)"; exit 1; }
for script in client/scripts/*.gd; do
  name=$(basename "$script")
  check "$name" "" --check-only --script "res://scripts/$name"
done
check "campaign review parser" "" --check-only --script ../tools/review_campaign.gd
check "campaign review behavior" "test_review_campaign: PASS" --verbose --script ../tools/test_review_campaign.gd

for script in client/scripts/test_*.gd; do
  harness=$(basename "$script" .gd)
  # Exit leaks need the retained object/resource identities from this same run.
  check "$harness harness" "$harness: PASS" --verbose --script "res://scripts/$harness.gd"
done

if [ "$fail" -ne 0 ]; then
  echo "Godot checks: FAIL (see diagnostics above)"
else
  echo "Godot checks: PASS"
fi
exit $fail
