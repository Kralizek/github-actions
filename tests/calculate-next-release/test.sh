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
  local period_value="$1"
  local scheme="${2:-periodic}"
  local prefix="${3:-r}"
  local period="${4:-month}"
  local period_format="${5:-}"
  local digits="${6:-4}"
  local output status
  output=$(mktemp)

  if SCHEME="$scheme" \
    PERIOD="$period" \
    PERIOD_FORMAT="$period_format" \
    PERIOD_VALUE="$period_value" \
    DIGITS="$digits" \
    TAG_PREFIX="$prefix" \
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

echo "First periodic monthly release"
first=$(calculate 202609)
assert_output "$first" 'release=202609-0001'
assert_output "$first" 'tag=r202609-0001'
assert_output "$first" 'previous-tag='
assert_output "$first" 'scheme=periodic'
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

echo "Reject period regression"
echo later > initial.txt
git add initial.txt
git commit -qm "Later commit"
assert_fails calculate 202609

echo "Do not reuse an older tag on HEAD after a later release exists"
git checkout -q HEAD~2
assert_fails calculate 202609
git checkout -q master

echo "Ignore malformed periodic tags"
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
custom=$(calculate 202609 periodic rel-)
assert_output "$custom" 'tag=rel-202609-0001'
rm -rf "$custom_repository"
cd "$repository"

echo "Support custom period formatting and sequence digits"
formatted_repository="$(mktemp -d)"
cd "$formatted_repository"
git init -q
git config user.name "Validation"
git config user.email "validation@example.invalid"
touch initial.txt
git add initial.txt
git commit -qm "Initial commit"
formatted=$(calculate 2026-09 periodic r month '%Y-%m' 2)
assert_output "$formatted" 'release=2026-09-01'
assert_output "$formatted" 'tag=r2026-09-01'
assert_output "$formatted" 'period=2026-09'
assert_output "$formatted" 'sequence=01'
rm -rf "$formatted_repository"
cd "$repository"

echo "Support yearly, weekly, and daily periods"
period_repository="$(mktemp -d)"
cd "$period_repository"
git init -q
git config user.name "Validation"
git config user.email "validation@example.invalid"
touch initial.txt
git add initial.txt
git commit -qm "Initial commit"
yearly=$(calculate 2026 periodic r year)
assert_output "$yearly" 'tag=r2026-0001'
weekly=$(calculate 202638 periodic r week)
assert_output "$weekly" 'tag=r202638-0001'
daily=$(calculate 20260916 periodic r day)
assert_output "$daily" 'tag=r20260916-0001'
rm -rf "$period_repository"
cd "$repository"

echo "Reject unsupported schemes and periods"
assert_fails calculate 202609 calendar
assert_fails calculate 202609 periodic r quarter

echo "Reject period formats that do not preserve chronological ordering"
assert_fails calculate 09-2026 periodic r month '%m-%Y'
assert_fails calculate 38-2026 periodic r week '%V-%G'
assert_fails calculate 16-09-2026 periodic r day '%d-%m-%Y'

echo "Reject unsupported period format tokens"
assert_fails calculate 202609 periodic r month '%Y%m%H'

echo "Reject invalid digit counts"
assert_fails calculate 202609 periodic r month '' 0
assert_fails calculate 202609 periodic r month '' 10

echo "Reject invalid rendered periods"
assert_fails calculate 202613
assert_fails calculate 20269

echo "Reject multiple current-period tags on HEAD"
git tag r202610-0002
git tag r202610-0003
assert_fails calculate 202610

echo "calculate-next-release tests passed"
