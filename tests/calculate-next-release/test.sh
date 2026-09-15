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
git tag v1.2.3

calculate() {
  local bump="$1"
  local channel="${2:-}"
  local minimum_version="${3:-}"
  local output status
  output=$(mktemp)

  if BUMP="$bump" \
    CHANNEL="$channel" \
    MINIMUM_VERSION="$minimum_version" \
    TAG_PREFIX="v" \
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

echo "Stable patch release"
patch_output=$(calculate patch)
assert_output "$patch_output" 'version=1.2.4'
assert_output "$patch_output" 'tag=v1.2.4'
assert_output "$patch_output" 'previous-tag=v1.2.3'
assert_output "$patch_output" 'base-version=1.2.4'
assert_output "$patch_output" 'prerelease=false'
assert_output "$patch_output" 'channel='

echo "Stable minor release"
minor_output=$(calculate minor)
assert_output "$minor_output" 'version=1.3.0'

echo "Stable major release"
major_output=$(calculate major)
assert_output "$major_output" 'version=2.0.0'

echo "Minimum version raises stable target"
floor_output=$(calculate minor '' 2.0.0)
assert_output "$floor_output" 'base-version=2.0.0'
assert_output "$floor_output" 'version=2.0.0'

echo "Minimum version does not lower calculated target"
low_floor_output=$(calculate minor '' 1.1.0)
assert_output "$low_floor_output" 'version=1.3.0'

echo "Minimum version also applies to prereleases"
floor_rc_output=$(calculate minor rc 2.0.0)
assert_output "$floor_rc_output" 'version=2.0.0-rc.1'

echo "First prerelease in a channel"
beta_output=$(calculate minor beta)
assert_output "$beta_output" 'version=1.3.0-beta.1'
assert_output "$beta_output" 'tag=v1.3.0-beta.1'
assert_output "$beta_output" 'base-version=1.3.0'
assert_output "$beta_output" 'prerelease=true'
assert_output "$beta_output" 'channel=beta'

git tag v1.3.0-beta.1
git tag v1.3.0-beta.2

echo "Increment existing prerelease channel"
next_beta_output=$(calculate minor beta)
assert_output "$next_beta_output" 'version=1.3.0-beta.3'

echo "Start independent prerelease channel"
rc_output=$(calculate minor rc)
assert_output "$rc_output" 'version=1.3.0-rc.1'

echo "Ignore malformed stable tags"
git tag v01.9.9
git tag v1.02.9
git tag v1.2.03
ignored_invalid_output=$(calculate patch)
assert_output "$ignored_invalid_output" 'previous-tag=v1.2.3'
assert_output "$ignored_invalid_output" 'version=1.2.4'

echo "Reject invalid minimum versions"
assert_fails calculate patch '' 01.2.3
assert_fails calculate patch '' 1.02.3
assert_fails calculate patch '' 1.2.03
assert_fails calculate patch '' 1.2.3-rc.1

echo "Reject invalid prerelease channels"
assert_fails calculate minor 'rc.1'
assert_fails calculate minor '01'

echo "calculate-next-release tests passed"
