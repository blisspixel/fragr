#!/usr/bin/env bash
# Fail unless every third-party GitHub Action uses a full commit SHA.
# Local actions that start with ./ are exempt. No network.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  shopt -s nullglob
  files=("$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "no workflow files to check" >&2
  exit 1
fi

fail=0
for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "missing workflow $file" >&2
    fail=1
    continue
  fi
  line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    code=${line%%#*}
    if [[ "$code" =~ uses:[[:space:]]*([^[:space:]]+) ]]; then
      uses=${BASH_REMATCH[1]}
      uses=${uses%\"}
      uses=${uses#\"}
      if [[ "$uses" == ./* ]]; then
        continue
      fi
      if [[ ! "$uses" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$ ]]; then
        echo "$file:$line_no: unpinned action: $uses" >&2
        fail=1
      fi
    fi
  done < "$file"
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "action pins ok"
