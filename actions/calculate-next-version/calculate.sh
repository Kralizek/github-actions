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

increment_version() {
  local version="$1"
  local major minor patch

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

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

apply_minimum_version() {
  local version="$1"

  if [ -n "$MINIMUM_VERSION" ] && version_greater_than "$MINIMUM_VERSION" "$version"; then
    printf '%s\n' "$MINIMUM_VERSION"
  else
    printf '%s\n' "$version"
  fi
}

calculate_base_from_tag() {
  local tag="$1"

  if [ -z "$tag" ]; then
    printf '%s\n' "${MINIMUM_VERSION:-0.1.0}"
  else
    apply_minimum_version "$(increment_version "${tag#"$TAG_PREFIX"}")"
  fi
}

find_latest_stable_tag() {
  git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-version:refname \
    | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
    | head -n 1 \
    || true
}

find_latest_stable_tag_excluding_head() {
  local head_commit tag tag_commit
  head_commit=$(git rev-parse HEAD)

  while IFS= read -r tag; do
    tag_commit=$(git rev-list -n 1 "$tag")
    if [ "$tag_commit" != "$head_commit" ]; then
      printf '%s\n' "$tag"
      return 0
    fi
  done < <(
    git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-version:refname \
      | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
      || true
  )
}

load_prerelease_tags() {
  local base_version="$1"
  local prerelease_base_prefix="${TAG_PREFIX}${base_version}-"
  local prerelease_base_pattern="^${escaped_prefix}${base_version//./\\.}-([0-9A-Za-z-]+)\.(0|[1-9][0-9]*)$"

  mapfile -t all_base_tags < <(
    git tag -l "${prerelease_base_prefix}*" \
      | grep -E "$prerelease_base_pattern" \
      | sort -V \
      || true
  )
}

find_highest_channel() {
  local base_version="$1"
  local prerelease_base_prefix="${TAG_PREFIX}${base_version}-"
  local tag suffix tag_channel highest_channel=''

  for tag in "${all_base_tags[@]}"; do
    suffix="${tag#"$prerelease_base_prefix"}"
    tag_channel="${suffix%.*}"
    if [ -z "$highest_channel" ] || [[ "$tag_channel" > "$highest_channel" ]]; then
      highest_channel="$tag_channel"
    fi
  done

  printf '%s\n' "$highest_channel"
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
escaped_channel=$(printf '%s' "$CHANNEL" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
latest_tag=$(find_latest_stable_tag)
previous_tag="$latest_tag"
reused_tag=''

if [ -n "$VERSION_INPUT" ]; then
  if [ -z "$CHANNEL" ]; then
    if ! validate_stable_version "$VERSION_INPUT"; then
      echo "Explicit stable version must be a stable Semantic Versioning version: $VERSION_INPUT"
      exit 1
    fi

    base_version="$VERSION_INPUT"
    next_version="$VERSION_INPUT"
    prerelease=false
  else
    explicit_prerelease_pattern="^${stable_version_pattern}-${escaped_channel}\.(0|[1-9][0-9]*)$"
    if [[ ! "$VERSION_INPUT" =~ $explicit_prerelease_pattern ]]; then
      echo "Explicit version must belong to prerelease channel ${CHANNEL} and use the form major.minor.patch-${CHANNEL}.number: $VERSION_INPUT"
      exit 1
    fi

    base_version="${VERSION_INPUT%%-*}"
    next_version="$VERSION_INPUT"
    prerelease=true
  fi
else
  if [ -z "$CHANNEL" ]; then
    mapfile -t current_stable_tags < <(
      git tag --points-at HEAD -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" \
        | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
        | sort -V \
        || true
    )

    if [ "${#current_stable_tags[@]}" -gt 1 ]; then
      echo "Multiple stable release tags point to HEAD: ${current_stable_tags[*]}"
      exit 1
    fi

    historical_tag=$(find_latest_stable_tag_excluding_head || true)
    historical_target=$(calculate_base_from_tag "$historical_tag")
    historical_target_tag="${TAG_PREFIX}${historical_target}"

    if [ "${#current_stable_tags[@]}" -eq 1 ] && [ "${current_stable_tags[0]}" = "$historical_target_tag" ]; then
      reused_tag="$historical_target_tag"
      previous_tag="$historical_tag"
      base_version="$historical_target"
      next_version="$historical_target"
      prerelease=false
    else
      base_version=$(calculate_base_from_tag "$latest_tag")
      next_version="$base_version"
      prerelease=false
    fi
  else
    base_version=$(calculate_base_from_tag "$latest_tag")
  fi
fi

if [ -z "$CHANNEL" ] && [ -n "$latest_tag" ]; then
  latest_version="${latest_tag#"$TAG_PREFIX"}"
  if version_greater_than "$latest_version" "$next_version"; then
    echo "Stable release $next_version cannot move backwards from latest stable release $latest_version." >&2
    exit 1
  fi
fi

if [ -n "$CHANNEL" ]; then
  stable_base_tag="${TAG_PREFIX}${base_version}"
  if git rev-parse -q --verify "refs/tags/${stable_base_tag}" >/dev/null; then
    echo "Cannot create prerelease ${base_version}-${CHANNEL} because stable tag ${stable_base_tag} already exists."
    exit 1
  fi

  prerelease_pattern="^${escaped_prefix}${base_version//./\\.}-${escaped_channel}\.(0|[1-9][0-9]*)$"

  mapfile -t current_channel_tags < <(
    git tag --points-at HEAD -l "${TAG_PREFIX}${base_version}-${CHANNEL}.*" \
      | grep -E "$prerelease_pattern" \
      | sort -V \
      || true
  )

  if [ "${#current_channel_tags[@]}" -gt 1 ]; then
    echo "Multiple ${CHANNEL} prerelease tags for ${base_version} point to HEAD: ${current_channel_tags[*]}"
    exit 1
  fi

  exact_tag="${TAG_PREFIX}${next_version:-}"
  exact_tag_on_head=false
  if [ -n "${next_version:-}" ] && git rev-parse -q --verify "refs/tags/${exact_tag}" >/dev/null; then
    if [ "$(git rev-list -n 1 "$exact_tag")" = "$(git rev-parse HEAD)" ]; then
      exact_tag_on_head=true
    fi
  fi

  if [ -z "$VERSION_INPUT" ] && [ "${#current_channel_tags[@]}" -eq 1 ]; then
    reused_tag="${current_channel_tags[0]}"
    next_version="${reused_tag#"$TAG_PREFIX"}"
  else
    load_prerelease_tags "$base_version"
    highest_channel=$(find_highest_channel "$base_version")

    if [ "$exact_tag_on_head" != true ] && [ -n "$highest_channel" ] && [[ "$CHANNEL" < "$highest_channel" ]]; then
      echo "Cannot move prerelease channel backwards from ${highest_channel} to ${CHANNEL} for ${base_version}."
      exit 1
    fi

    if [ -n "$VERSION_INPUT" ]; then
      if [ "$exact_tag_on_head" = true ]; then
        reused_tag="$exact_tag"
      fi
    else
      latest_channel_tag=$(
        printf '%s\n' "${all_base_tags[@]}" \
          | grep -E "$prerelease_pattern" \
          | sort -V \
          | tail -n 1 \
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
  fi

  prerelease=true
fi

next_tag="${TAG_PREFIX}${next_version}"

release_notes_start_tag="$previous_tag"
if [ -z "$CHANNEL" ] && [ -n "$VERSION_INPUT" ] && git rev-parse -q --verify "refs/tags/${next_tag}" >/dev/null; then
  if [ "$(git rev-list -n 1 "$next_tag")" = "$(git rev-parse HEAD)" ]; then
    release_notes_start_tag=$(find_latest_stable_tag_excluding_head || true)
  fi
elif [ -n "$CHANNEL" ]; then
  release_notes_start_tag=$(
    git tag -l "${TAG_PREFIX}${base_version}-${CHANNEL}.*" --sort=-version:refname \
      | grep -E "$prerelease_pattern" \
      | grep -Fxv "$next_tag" \
      | head -n 1 \
      || true
  )

  if [ -z "$release_notes_start_tag" ]; then
    release_notes_start_tag="$previous_tag"
  fi
fi

if [ -z "$reused_tag" ] && git rev-parse -q --verify "refs/tags/${next_tag}" >/dev/null; then
  tag_commit=$(git rev-list -n 1 "$next_tag")
  head_commit=$(git rev-parse HEAD)
  if [ "$tag_commit" = "$head_commit" ]; then
    reused_tag="$next_tag"
  else
    echo "Tag ${next_tag} already exists on a different commit."
    exit 1
  fi
fi

echo "Previous stable release: ${previous_tag:-none}"
if [ -n "$reused_tag" ]; then
  echo "Reusing release tag on HEAD: $reused_tag"
elif [ -n "$VERSION_INPUT" ]; then
  echo "Using explicit release: $next_tag"
else
  echo "Next release: $next_tag"
fi
echo "previous-tag=$previous_tag" >> "$GITHUB_OUTPUT"
echo "release-notes-start-tag=$release_notes_start_tag" >> "$GITHUB_OUTPUT"
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
echo "version=$next_version" >> "$GITHUB_OUTPUT"
echo "tag=$next_tag" >> "$GITHUB_OUTPUT"
echo "prerelease=$prerelease" >> "$GITHUB_OUTPUT"
echo "channel=$CHANNEL" >> "$GITHUB_OUTPUT"
