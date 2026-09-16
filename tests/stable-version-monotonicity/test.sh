#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/actions/calculate-next-release/validate-stable-version.sh"
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

validate() {
  CHANNEL="${1:-}" \
  VERSION_INPUT="${2:-}" \
  TAG_PREFIX=v \
    bash "$script"
}

echo "Allow equal explicit stable version"
validate '' 1.3.0

echo "Allow later explicit stable version"
validate '' 1.3.1
validate '' 1.4.0
validate '' 2.0.0

echo "Reject explicit stable version regression"
if validate '' 1.2.9 >/dev/null 2>&1; then
  echo "Expected explicit stable regression to fail" >&2
  exit 1
fi

echo "Do not apply stable monotonicity to prerelease overrides"
validate rc 1.2.0-rc.1

echo "Ignore malformed stable overrides so calculate.sh retains validation ownership"
validate '' not-semver

echo "Ignore malformed stable tags when choosing the latest stable release"
git tag v99.0.00
validate '' 1.3.0

echo "stable-version-monotonicity tests passed"
