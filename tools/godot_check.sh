#!/usr/bin/env bash
# Headless Godot checks for the client: import the project, parse every script,
# run the harnesses. Godot can exit 0 with errors in its log, so the log lines
# are the verdict. Set GODOT_BIN to a 4.7.2-stable binary, or have `godot` on PATH.
# Build fragr-server --release --locked first; local campaign checks spawn it.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
"$GODOT" --version || { echo "godot binary not found (set GODOT_BIN)"; exit 1; }
fail=0

# Godot may print an error and return zero, or fail without a script diagnostic.
# A PASS line cannot cancel an earlier error in the same run.
check() {
  local label="$1" marker="$2" out status
  shift 2
  out=$("$GODOT" --headless --path client "$@" 2>&1)
  status=$?
  # Engine severity labels are uppercase. Verbose socket diagnostics also say
  # "error", including the intentional child crash in test_local_campaign.
  if [ "$status" -ne 0 ] || printf '%s\n' "$out" | grep -qE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:'; then
    echo "FAIL $label (exit $status)"
    printf '%s\n' "$out"
    fail=1
    return 1
  fi
  if [ -n "$marker" ] && ! printf '%s\n' "$out" | grep -qF "$marker"; then
    echo "FAIL $label (missing $marker)"
    printf '%s\n' "$out"
    fail=1
    return 1
  fi
  echo "ok   $label"
}

# Parsing with a failed import only produces secondary missing-resource errors.
check import "" --import || { echo "Godot checks: FAIL (import)"; exit 1; }
for script in client/scripts/*.gd; do
  name=$(basename "$script")
  check "$name" "" --check-only --script "res://scripts/$name"
done

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
