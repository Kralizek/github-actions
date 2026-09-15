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

reused_tag=''

if [ -n "$CHANNEL" ]; then
  current_stable_tag=$(
    git tag --points-at HEAD -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" \
      | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
      | head -n 1 \
      || true
  )

  if [ -n "$current_stable_tag" ]; then
    echo "Cannot create prerelease ${base_version}-${CHANNEL} because stable tag ${current_stable_tag} already points to HEAD."
    exit 1
  fi

  prerelease_base_prefix="${TAG_PREFIX}${base_version}-"
  prerelease_base_pattern="^${escaped_prefix}${base_version//./\\.}-([0-9A-Za-z-]+)\.(0|[1-9][0-9]*)$"

  mapfile -t current_base_tags < <(
    git tag --points-at HEAD -l "${prerelease_base_prefix}*" \
      | grep -E "$prerelease_base_pattern" \
      | sort -V \
      || true
  )

  highest_channel=''
  for tag in "${current_base_tags[@]}"; do
    suffix="${tag#"$prerelease_base_prefix"}"
    tag_channel="${suffix%.*}"
    if [ -z "$highest_channel" ] || [[ "$tag_channel" > "$highest_channel" ]]; then
      highest_channel="$tag_channel"
    fi
  done

  if [ -n "$highest_channel" ] && [[ "$CHANNEL" < "$highest_channel" ]]; then
    echo "Cannot move prerelease channel backwards from ${highest_channel} to ${CHANNEL} for ${base_version} on HEAD."
    exit 1
  fi

  escaped_channel=$(printf '%s' "$CHANNEL" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
  prerelease_pattern="^${escaped_prefix}${base_version//./\\.}-${escaped_channel}\.(0|[1-9][0-9]*)$"

  mapfile -t current_channel_tags < <(
    printf '%s\n' "${current_base_tags[@]}" \
      | grep -E "$prerelease_pattern" \
      | sort -V \
      || true
  )

  if [ "${#current_channel_tags[@]}" -gt 1 ]; then
    echo "Multiple ${CHANNEL} prerelease tags for ${base_version} point to HEAD: ${current_channel_tags[*]}"
    exit 1
  fi

  if [ "${#current_channel_tags[@]}" -eq 1 ]; then
    reused_tag="${current_channel_tags[0]}"
    next_version="${reused_tag#"$TAG_PREFIX"}"
  else
    latest_channel_tag=$(
      git tag -l "${TAG_PREFIX}${base_version}-${CHANNEL}.*" --sort=-version:refname \
        | grep -E "$prerelease_pattern" \
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
  fi

  prerelease=true
else
  next_version="$base_version"
  prerelease=false
fi

next_tag="${TAG_PREFIX}${next_version}"

if [ -z "$reused_tag" ] && git rev-parse -q --verify "refs/tags/${next_tag}" >/dev/null; then
  echo "Tag ${next_tag} already exists."
  exit 1
fi

echo "Previous stable release: ${latest_tag:-none}"
if [ -n "$reused_tag" ]; then
  echo "Reusing prerelease tag on HEAD: $reused_tag"
else
  echo "Next release: $next_tag"
fi
echo "previous-tag=$latest_tag" >> "$GITHUB_OUTPUT"
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
echo "version=$next_version" >> "$GITHUB_OUTPUT"
echo "tag=$next_tag" >> "$GITHUB_OUTPUT"
echo "prerelease=$prerelease" >> "$GITHUB_OUTPUT"
echo "channel=$CHANNEL" >> "$GITHUB_OUTPUT"
