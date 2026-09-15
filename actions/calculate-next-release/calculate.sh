#!/usr/bin/env bash
set -euo pipefail

stable_version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'

validate_stable_version() {
  local value="$1"
  [[ "$value" =~ ^${stable_version_pattern}$ ]]
}

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

case "$BUMP" in
  patch|minor|major)
    ;;
  *)
    echo "Unsupported version bump: $BUMP"
    exit 1
    ;;
esac

if [ -n "$CHANNEL" ]; then
  if [[ ! "$CHANNEL" =~ ^[0-9A-Za-z-]+$ ]]; then
    echo "Prerelease channel must be a valid SemVer identifier: $CHANNEL"
    exit 1
  fi

  if [[ "$CHANNEL" =~ ^[0-9]+$ && "$CHANNEL" =~ ^0[0-9]+$ ]]; then
    echo "Numeric prerelease channel must not contain leading zeroes: $CHANNEL"
    exit 1
  fi
fi

if [ -n "$MINIMUM_VERSION" ] && ! validate_stable_version "$MINIMUM_VERSION"; then
  echo "Minimum version must be a stable Semantic Versioning version: $MINIMUM_VERSION"
  exit 1
fi

escaped_prefix=$(printf '%s' "$TAG_PREFIX" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
latest_tag=$(
  git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-version:refname \
    | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
    | head -n 1 \
    || true
)

if [ -z "$latest_tag" ]; then
  base_version="${MINIMUM_VERSION:-0.1.0}"
else
  version="${latest_tag#"$TAG_PREFIX"}"
  IFS=. read -r major minor patch <<< "$version"

  case "$BUMP" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
  esac

  base_version="${major}.${minor}.${patch}"

  if [ -n "$MINIMUM_VERSION" ] && version_greater_than "$MINIMUM_VERSION" "$base_version"; then
    base_version="$MINIMUM_VERSION"
  fi
fi

if [ -n "$CHANNEL" ]; then
  escaped_channel=$(printf '%s' "$CHANNEL" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
  latest_channel_tag=$(
    git tag -l "${TAG_PREFIX}${base_version}-${CHANNEL}.*" --sort=-version:refname \
      | grep -E "^${escaped_prefix}${base_version//./\\.}-${escaped_channel}\.(0|[1-9][0-9]*)$" \
      | head -n 1 \
      || true
  )

  if [ -z "$latest_channel_tag" ]; then
    channel_number=1
  else
    channel_number="${latest_channel_tag##*.}"
    channel_number=$((channel_number + 1))
  fi

  next_version="${base_version}-${CHANNEL}.${channel_number}"
  prerelease=true
else
  next_version="$base_version"
  prerelease=false
fi

next_tag="${TAG_PREFIX}${next_version}"

if git rev-parse -q --verify "refs/tags/${next_tag}" >/dev/null; then
  echo "Tag ${next_tag} already exists."
  exit 1
fi

echo "Previous stable release: ${latest_tag:-none}"
echo "Next release: $next_tag"
echo "previous-tag=$latest_tag" >> "$GITHUB_OUTPUT"
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
echo "version=$next_version" >> "$GITHUB_OUTPUT"
echo "tag=$next_tag" >> "$GITHUB_OUTPUT"
echo "prerelease=$prerelease" >> "$GITHUB_OUTPUT"
echo "channel=$CHANNEL" >> "$GITHUB_OUTPUT"
