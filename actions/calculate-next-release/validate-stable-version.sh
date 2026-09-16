#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VERSION_INPUT:-}" ] || [ -n "${CHANNEL:-}" ]; then
  exit 0
fi

stable_version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'

if [[ ! "$VERSION_INPUT" =~ ^${stable_version_pattern}$ ]]; then
  # calculate.sh owns the user-facing validation for malformed explicit versions.
  exit 0
fi

escaped_prefix=$(printf '%s' "$TAG_PREFIX" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
latest_tag=$(
  git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-version:refname \
    | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
    | head -n 1 \
    || true
)

if [ -z "$latest_tag" ]; then
  exit 0
fi

latest_version="${latest_tag#"$TAG_PREFIX"}"

version_greater_than() {
  local left="$1"
  local right="$2"
  local left_major left_minor left_patch right_major right_minor right_patch

  IFS=. read -r left_major left_minor left_patch <<< "$left"
  IFS=. read -r right_major right_minor right_patch <<< "$right"

  if (( left_major != right_major )); then
    (( left_major > right_major ))
    return
  fi

  if (( left_minor != right_minor )); then
    (( left_minor > right_minor ))
    return
  fi

  (( left_patch > right_patch ))
}

if version_greater_than "$latest_version" "$VERSION_INPUT"; then
  echo "Explicit stable version $VERSION_INPUT cannot move backwards from latest stable release $latest_version." >&2
  exit 1
fi
