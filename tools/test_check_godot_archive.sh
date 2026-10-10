#!/usr/bin/env bash
# Prove the Godot pin helper accepts a matching digest and rejects one flipped byte.
# This does not download a Godot editor.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

printf 'pin-fixture' > "$tmp/sample.bin"
if command -v sha512sum >/dev/null 2>&1; then
  hash=$(sha512sum -- "$tmp/sample.bin" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
  hash=$(shasum -a 512 -- "$tmp/sample.bin" | awk '{ print $1 }')
else
  echo "sha512sum or shasum is required" >&2
  exit 1
fi

printf '%s  sample.bin\n' "$hash" > "$tmp/SHA512-SUMS.txt"
FRAGR_GODOT_SUMS="$tmp/SHA512-SUMS.txt" bash "$here/check_godot_archive.sh" "$tmp/sample.bin" sample.bin

printf 'x' >> "$tmp/sample.bin"
if FRAGR_GODOT_SUMS="$tmp/SHA512-SUMS.txt" bash "$here/check_godot_archive.sh" "$tmp/sample.bin" sample.bin; then
  echo "tampered archive was accepted" >&2
  exit 1
fi

echo "godot archive pin helper: PASS"
