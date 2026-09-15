#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/actions/validate-release/validate.sh"
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
git tag v1.2.3-rc.1
git tag v1.2.3+build.01
git tag v1.2.3-rc.1+build.7

validate() {
  local tag="$1"
  local prerelease="$2"
  local output status
  output=$(mktemp)

  if RELEASE_TAG="$tag" \
    RELEASE_IS_PRERELEASE="$prerelease" \
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

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

echo "Accept stable SemVer tag"
stable_output=$(validate v1.2.3 false)
grep -qx 'version=1.2.3' <<< "$stable_output"

echo "Accept prerelease SemVer tag"
prerelease_output=$(validate v1.2.3-rc.1 true)
grep -qx 'version=1.2.3-rc.1' <<< "$prerelease_output"

echo "Accept build metadata"
build_output=$(validate v1.2.3+build.01 false)
grep -qx 'version=1.2.3+build.01' <<< "$build_output"
prerelease_build_output=$(validate v1.2.3-rc.1+build.7 true)
grep -qx 'version=1.2.3-rc.1+build.7' <<< "$prerelease_build_output"

echo "Reject invalid core versions"
assert_fails validate v01.2.3 false
assert_fails validate v1.02.3 false
assert_fails validate v1.2.03 false

echo "Reject invalid prerelease forms"
assert_fails validate v1.2.3-rc..1 true
assert_fails validate v1.2.3-.rc true
assert_fails validate v1.2.3-01 true

echo "Reject prerelease flag mismatches"
assert_fails validate v1.2.3 true
assert_fails validate v1.2.3-rc.1 false
assert_fails validate v1.2.3 maybe

echo "Reject tags that do not point to HEAD"
echo changed > initial.txt
git add initial.txt
git commit -qm "Second commit"
assert_fails validate v1.2.3 false

echo "validate-release tests passed"
