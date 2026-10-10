#!/usr/bin/env bash
# The pin checker accepts a SHA and rejects a floating tag. No network.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

cat > "$tmp/pinned.yml" <<'EOF'
jobs:
  test:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - uses: ./tools/local
EOF
bash "$here/check_action_pins.sh" "$tmp/pinned.yml"

cat > "$tmp/floating.yml" <<'EOF'
jobs:
  test:
    steps:
      - uses: actions/checkout@v7
EOF
if bash "$here/check_action_pins.sh" "$tmp/floating.yml"; then
  echo "floating action tag was accepted" >&2
  exit 1
fi

echo "action pin helper: PASS"
