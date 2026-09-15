#!/usr/bin/env bash
set -euo pipefail

if [[ "$RELEASE_IS_PRERELEASE" != "true" && "$RELEASE_IS_PRERELEASE" != "false" ]]; then
  echo "Prerelease flag must be true or false: $RELEASE_IS_PRERELEASE" >&2
  exit 1
fi

if [[ "$RELEASE_TAG" != v* ]]; then
  echo "Release tag must use the v prefix: $RELEASE_TAG" >&2
  exit 1
fi

version="${RELEASE_TAG#v}"
semver_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'

if [[ ! "$version" =~ $semver_pattern ]]; then
  echo "Release tag is not a valid Semantic Versioning tag: $RELEASE_TAG" >&2
  exit 1
fi

without_build="${version%%+*}"
prerelease_part=''
if [[ "$without_build" == *-* ]]; then
  prerelease_part="${without_build#*-}"
fi

if [ -n "$prerelease_part" ]; then
  IFS='.' read -r -a identifiers <<< "$prerelease_part"
  for identifier in "${identifiers[@]}"; do
    if [[ "$identifier" =~ ^[0-9]+$ && "$identifier" =~ ^0[0-9]+$ ]]; then
      echo "Numeric prerelease identifiers must not contain leading zeroes: $RELEASE_TAG" >&2
      exit 1
    fi
  done
fi

release_commit="$(git rev-parse "$RELEASE_TAG^{commit}")"
head_commit="$(git rev-parse HEAD)"
if [[ "$release_commit" != "$head_commit" ]]; then
  echo "Release tag $RELEASE_TAG does not point to the checked-out commit." >&2
  exit 1
fi

actual_prerelease=false
if [ -n "$prerelease_part" ]; then
  actual_prerelease=true
fi

if [[ "$RELEASE_IS_PRERELEASE" != "$actual_prerelease" ]]; then
  if [[ "$actual_prerelease" == "true" ]]; then
    echo "Prerelease tag $RELEASE_TAG must be published as a GitHub prerelease." >&2
  else
    echo "Stable tag $RELEASE_TAG must not be published as a GitHub prerelease." >&2
  fi
  exit 1
fi

echo "version=$version" >> "$GITHUB_OUTPUT"
