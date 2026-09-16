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

git tag v1.3.0

calculate() {
  local channel="${1:-}"
  local version_input="${2:-}"
  local output status
  output=$(mktemp)

  if BUMP=minor \
    CHANNEL="$channel" \
    VERSION_INPUT="$version_input" \
    MINIMUM_VERSION='' \
    TAG_PREFIX=v \
    GITHUB_OUTPUT="$output" \
      bash "$script" >/dev/null; then
    status=0
  else
    status=$?
  fi

  rm -f "$output"
  return "$status"
}

echo "Allow equal explicit stable version"
calculate '' 1.3.0

echo "Allow later explicit stable version"
calculate '' 1.3.1
calculate '' 1.4.0
calculate '' 2.0.0

echo "Reject explicit stable version regression"
if calculate '' 1.2.9 >/dev/null 2>&1; then
  echo "Expected explicit stable regression to fail" >&2
  exit 1
fi

echo "Keep malformed explicit versions under calculator validation"
if calculate '' not-semver >/dev/null 2>&1; then
  echo "Expected malformed explicit stable version to fail" >&2
  exit 1
fi

echo "Ignore malformed stable tags when choosing the latest stable release"
git tag v99.0.00
calculate '' 1.3.0

echo "stable-version-monotonicity tests passed"
