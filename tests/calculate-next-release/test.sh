#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/actions/calculate-next-release/dist/index.js"
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
  local date="$1"
  local period="${2:-month}"
  local format="${3:-}"
  local scheme="${4:-periodic}"
  local output status
  output=$(mktemp)

  if INPUT_SCHEME="$scheme" \
    INPUT_PERIOD="$period" \
    INPUT_FORMAT="$format" \
    RELEASE_DATE="$date" \
    GITHUB_OUTPUT="$output" \
      node "$script" >/dev/null; then
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

echo "Default monthly release"
first=$(calculate 2026-09-16)
assert_output "$first" 'release=r202609-0001'
assert_output "$first" 'tag=r202609-0001'
assert_output "$first" 'previous-tag='
assert_output "$first" 'scheme=periodic'
assert_output "$first" 'period=202609'
assert_output "$first" 'sequence=0001'
git tag r202609-0001

echo "Reuse latest release tag on HEAD"
rerun=$(calculate 2026-09-16)
assert_output "$rerun" 'tag=r202609-0001'
assert_output "$rerun" 'previous-tag='

echo "Advance monthly sequence"
echo second > initial.txt
git add initial.txt
git commit -qm "Second release"
second=$(calculate 2026-09-17)
assert_output "$second" 'tag=r202609-0002'
assert_output "$second" 'previous-tag=r202609-0001'
git tag r202609-0002

echo "Reset sequence in a new month"
echo october > initial.txt
git add initial.txt
git commit -qm "October release"
october=$(calculate 2026-10-01)
assert_output "$october" 'tag=r202610-0001'
assert_output "$october" 'previous-tag=r202609-0002'
git tag r202610-0001

echo "Reject period regression"
echo later > initial.txt
git add initial.txt
git commit -qm "Later commit"
assert_fails calculate 2026-09-30

echo "Ignore malformed tags"
git tag r202699-9999
git tag r202610-0000
november=$(calculate 2026-11-01)
assert_output "$november" 'tag=r202611-0001'

echo "Support each period default"
yearly=$(calculate 2027-02-01 year)
assert_output "$yearly" 'tag=r2027-0001'
weekly=$(calculate 2027-02-01 week)
assert_output "$weekly" 'tag=r202705-0001'
daily=$(calculate 2027-02-01 day)
assert_output "$daily" 'tag=r20270201-0001'

echo "Support custom rendering and sequence width"
custom_repository="$(mktemp -d)"
cd "$custom_repository"
git init -q
git config user.name "Validation"
git config user.email "validation@example.invalid"
touch initial.txt
git add initial.txt
git commit -qm "Initial commit"
custom=$(calculate 2026-09-16 month 'release-{date:%Y-%m}.{sequence:6}')
assert_output "$custom" 'tag=release-2026-09.000001'
assert_output "$custom" 'period=2026-09'
assert_output "$custom" 'sequence=000001'
git tag release-2026-09.000001

echo "Semantic ordering does not depend on token order"
echo next > initial.txt
git add initial.txt
git commit -qm "Next custom release"
reverse=$(calculate 2026-09-17 month '{sequence:3}-r{date:%Y%m}')
assert_output "$reverse" 'tag=001-r202609'
git tag 001-r202609
echo another > initial.txt
git add initial.txt
git commit -qm "Another custom release"
reverse_next=$(calculate 2026-09-18 month '{sequence:3}-r{date:%Y%m}')
assert_output "$reverse_next" 'tag=002-r202609'
rm -rf "$custom_repository"
cd "$repository"

echo "Reject unsupported schemes and periods"
assert_fails calculate 2026-09-16 month '' calendar
assert_fails calculate 2026-09-16 quarter

echo "Reject malformed format grammar"
assert_fails calculate 2026-09-16 month 'r{date:%Y%m}'
assert_fails calculate 2026-09-16 month 'r{sequence:4}'
assert_fails calculate 2026-09-16 month 'r{date:%Y%m}-{sequence:0}'
assert_fails calculate 2026-09-16 month 'r{date:%m}-{sequence:4}'
assert_fails calculate 2026-09-16 month 'r{date:%Y%m%d}-{sequence:4}'
assert_fails calculate 2026-09-16 week 'r{date:%Y%V}-{sequence:4}'

echo "calculate-next-release tests passed"
