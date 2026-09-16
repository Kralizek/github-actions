#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/actions/calculate-next-release/calculate.sh"
repository="$(mktemp -d)"
trap 'rm -rf "$repository"' EXIT

cd "$repository"
git init -q
git config user.name "Validation"
git config user.email "validation@example.invalid"
touch initial.txt
git add initial.txt
git commit -qm "Initial commit"

calculate() {
  local period="$1"
  local scheme="${2:-calendar}"
  local prefix="${3:-r}"
  local output status
  output=$(mktemp)

  if SCHEME="$scheme" \
    TAG_PREFIX="$prefix" \
    CALENDAR_PERIOD="$period" \
    GITHUB_OUTPUT="$output" \
      bash "$script" >/dev/null; then
    status=0
  else
    status=$?
  fi

  if [ "$status" -ne 0 ]; then
    rm -f "$output"
    return "$status"
  fi

  cat "$output"
  rm -f "$output"
}

assert_output() {
  local output="$1"
  local expected="$2"
  grep -qx "$expected" <<< "$output"
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

echo "First calendar release"
first=$(calculate 202609)
assert_output "$first" 'release=202609-0001'
assert_output "$first" 'tag=r202609-0001'
assert_output "$first" 'previous-tag='
assert_output "$first" 'scheme=calendar'
assert_output "$first" 'period=202609'
assert_output "$first" 'sequence=0001'

git tag r202609-0001

echo "Reuse latest release tag on HEAD"
rerun=$(calculate 202609)
assert_output "$rerun" 'tag=r202609-0001'
assert_output "$rerun" 'previous-tag='

echo "Advance release sequence"
echo second > initial.txt
git add initial.txt
git commit -qm "Second release"
second=$(calculate 202609)
assert_output "$second" 'tag=r202609-0002'
assert_output "$second" 'previous-tag=r202609-0001'
git tag r202609-0002

echo "Reset sequence in a new month"
echo october > initial.txt
git add initial.txt
git commit -qm "October release"
october=$(calculate 202610)
assert_output "$october" 'tag=r202610-0001'
assert_output "$october" 'previous-tag=r202609-0002'
git tag r202610-0001

echo "Reject calendar period regression"
echo later > initial.txt
git add initial.txt
git commit -qm "Later commit"
assert_fails calculate 202609

echo "Do not reuse an older tag on HEAD after a later release exists"
git checkout -q HEAD~2
assert_fails calculate 202609
git checkout -q master

echo "Ignore malformed calendar tags"
git tag r202699-9999
git tag r202610-0000
november=$(calculate 202611)
assert_output "$november" 'tag=r202611-0001'

echo "Support a custom prefix"
custom_repository="$(mktemp -d)"
cd "$custom_repository"
git init -q
git config user.name "Validation"
git config user.email "validation@example.invalid"
touch initial.txt
git add initial.txt
git commit -qm "Initial commit"
custom=$(calculate 202609 calendar rel-)
assert_output "$custom" 'tag=rel-202609-0001'
rm -rf "$custom_repository"
cd "$repository"

echo "Reject unsupported schemes"
assert_fails calculate 202609 weekly

echo "Reject invalid periods"
assert_fails calculate 202613
assert_fails calculate 20269

echo "Reject multiple current-period tags on HEAD"
git tag r202610-0002
git tag r202610-0003
assert_fails calculate 202610

echo "calculate-next-release tests passed"
