#!/usr/bin/env bash
# Fault-inject the verifier itself. No Godot install or user config needed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .agents
fake=$(mktemp "$PWD/.agents/godot-check-XXXXXX")
trap 'rm -f "$fake"' EXIT
cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *--version*) echo '4.7.2 verifier fixture'; exit 0 ;;
  *--import*)
    case "$CASE" in
      import-exit) exit 7 ;;
      import-error) echo 'ERROR: import fixture'; exit 0 ;;
    esac
    exit 0 ;;
  *--check-only*) exit 0 ;;
esac
name=$(basename "${!#}" .gd)
case "$CASE" in
  missing-pass) exit 0 ;;
  error-and-pass) echo 'SCRIPT ERROR: fixture' ;;
  debug-socket) echo 'Socket error: 10054.' ;;
  long-error-and-pass|long-pass)
    if [ "$name" = test_actor_state ]; then
      if [ "$CASE" = long-error-and-pass ]; then echo 'SCRIPT ERROR: large fixture'; fi
      if [ "$CASE" = long-pass ]; then echo "$name: PASS"; fi
      # Exceed pipe buffers after an early match, independent of scheduling.
      printf '%01048576d\n' 0
      if [ "$CASE" = long-error-and-pass ]; then echo "$name: PASS"; fi
      exit 0
    fi
    ;;
  verbose-failure)
    case "$*" in *--verbose*) echo 'retained-object-identity-fixture' ;; esac
    echo 'ERROR: exit resource fixture'
    for line in {1..30}; do echo "diagnostic continuation $line"; done
    ;;
esac
echo "$name: PASS"
if [ "$CASE" = exit-and-pass ]; then exit 9; fi
FAKE
chmod +x "$fake"
for scenario in pass debug-socket import-exit import-error missing-pass error-and-pass exit-and-pass long-error-and-pass long-pass verbose-failure; do
  status=0
  output=$(CASE="$scenario" GODOT_BIN="$fake" bash tools/godot_check.sh 2>&1) || status=$?
  expected_pass=false
  if [ "$scenario" = pass ] || [ "$scenario" = debug-socket ] || [ "$scenario" = long-pass ]; then expected_pass=true; fi
  if { "$expected_pass" && [ "$status" -ne 0 ]; } ||
     { ! "$expected_pass" && [ "$status" -eq 0 ]; }; then
    echo "FAIL godot verifier scenario: $scenario (exit $status)"
    exit 1
  fi
  if [ "$scenario" = verbose-failure ] && ! grep -qF retained-object-identity-fixture <<<"$output"; then
    echo "FAIL godot verifier discarded verbose failure identity"
    exit 1
  fi
  summary=FAIL
  if "$expected_pass"; then summary=PASS; fi
  if ! grep -qF "Godot checks: $summary" <<<"$output"; then
    echo "FAIL godot verifier scenario: $scenario (missing aggregate $summary)"
    exit 1
  fi
  echo "ok   godot verifier scenario: $scenario"
done
