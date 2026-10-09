#!/usr/bin/env bash
# Check one downloaded Godot archive against the committed SHA-512 pin.
# The pin file is the pass/fail source. A fresh upstream sums file is not.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: check_godot_archive.sh <file> <archive-name>" >&2
  exit 2
fi

file=$1
name=$2
here=$(cd "$(dirname "$0")" && pwd)
sums=${FRAGR_GODOT_SUMS:-$here/godot/SHA512-SUMS.txt}

if [ ! -f "$file" ]; then
  echo "missing archive $file" >&2
  exit 1
fi
if [ ! -f "$sums" ]; then
  echo "missing Godot pin $sums" >&2
  exit 1
fi

expected=$(awk -v name="$name" '$2 == name { print $1; exit }' "$sums")
if [ -z "${expected}" ]; then
  echo "no pinned digest for $name" >&2
  exit 1
fi

if command -v sha512sum >/dev/null 2>&1; then
  actual=$(sha512sum -- "$file" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 512 -- "$file" | awk '{ print $1 }')
else
  echo "sha512sum or shasum is required" >&2
  exit 1
fi

if [ "$actual" != "$expected" ]; then
  echo "digest mismatch for $name" >&2
  exit 1
fi

echo "godot archive pin ok: $name"
