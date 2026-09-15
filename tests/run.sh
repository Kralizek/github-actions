#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob

tests=("$root"/tests/*/test.sh)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "No Bash test suites found under tests/*/test.sh."
  exit 1
fi

for test_script in "${tests[@]}"; do
  suite="$(basename "$(dirname "$test_script")")"
  echo "::group::Test $suite"
  bash "$test_script"
  echo "::endgroup::"
done
