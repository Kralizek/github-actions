#!/usr/bin/env bash
set -euo pipefail

stable_version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'

case "$BUMP" in
  patch|minor|major)
    ;;
  *)
    echo "Unsupported version bump: $BUMP"
    exit 1
    ;;
esac

escaped_prefix=$(printf '%s' "$TAG_PREFIX" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
latest_tag=$(
  git tag -l "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" --sort=-version:refname \
    | grep -E "^${escaped_prefix}${stable_version_pattern}$" \
    | head -n 1 \
    || true
)

if [ -z "$latest_tag" ]; then
  echo "No stable SemVer release tag exists with prefix '$TAG_PREFIX'."
  exit 1
fi

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

next_version="${major}.${minor}.${patch}"
next_tag="${TAG_PREFIX}${next_version}"

if git rev-parse -q --verify "refs/tags/${next_tag}" >/dev/null; then
  echo "Tag ${next_tag} already exists."
  exit 1
fi

echo "Previous release: $latest_tag"
echo "Next release: $next_tag"
echo "previous-tag=$latest_tag" >> "$GITHUB_OUTPUT"
echo "version=$next_version" >> "$GITHUB_OUTPUT"
echo "tag=$next_tag" >> "$GITHUB_OUTPUT"
