#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_TAG:?tag required}"
: "${RELEASE_TARGET:?target required}"
: "${RELEASE_REPOSITORY:?repository required}"
: "${GH_TOKEN:?GITHUB_TOKEN required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

if [[ -n "${RELEASE_BODY:-}" && -n "${RELEASE_BODY_FILE:-}" ]]; then
  echo "::error::body and body-file are mutually exclusive" >&2
  exit 1
fi
if [[ -n "${NOTES_START_TAG:-}" && ( -n "${RELEASE_BODY:-}" || -n "${RELEASE_BODY_FILE:-}" ) ]]; then
  echo "::error::release-notes-start-tag cannot be combined with explicit notes" >&2
  exit 1
fi
if [[ -n "${RELEASE_BODY_FILE:-}" && ! -f "$RELEASE_BODY_FILE" ]]; then
  echo "::error::body-file does not exist: $RELEASE_BODY_FILE" >&2
  exit 1
fi

if [[ "$RELEASE_PRERELEASE" != true && "$RELEASE_PRERELEASE" != false ]]; then
  echo "::error::prerelease must be true or false" >&2
  exit 1
fi
if [[ "${RELEASE_DRAFT:-false}" != true && "${RELEASE_DRAFT:-false}" != false ]]; then
  echo "::error::draft must be true or false" >&2
  exit 1
fi
if [[ ! "$RELEASE_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "::error::Invalid release tag" >&2
  exit 1
fi

# Fetch the remote tag, including annotated tag peeling; never trust a local-only tag.
if git ls-remote --exit-code --tags origin "refs/tags/$RELEASE_TAG" >/dev/null 2>&1; then
  git fetch --force --no-tags origin "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"
  tagged_sha=$(git rev-parse "$RELEASE_TAG^{commit}")
  if [[ "$tagged_sha" != "$RELEASE_TARGET" ]]; then
    echo "::error::Tag $RELEASE_TAG points to $tagged_sha, expected $RELEASE_TARGET." >&2
    exit 1
  fi
else
  # An ls-remote error is not proof that a tag is absent. Check connectivity first.
  git ls-remote origin HEAD >/dev/null
fi

release_json=''
created=false

# gh api's exit status distinguishes a successful response from failure. Only
# a verified 404 means that a new release may be created.
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT
if gh api --include "repos/$RELEASE_REPOSITORY/releases/tags/$RELEASE_TAG" > "$response_file" 2>&1; then
  release_json=$(sed '1,/^\r\{0,1\}$/d' "$response_file")
else
  status=$(awk '/^HTTP\// { print $2; exit }' "$response_file")
  if [[ "$status" != 404 ]]; then
    echo "::error::GitHub release lookup failed (HTTP ${status:-unknown})." >&2
    cat "$response_file" >&2
    exit 1
  fi
fi

if [[ -z "$release_json" ]]; then
  # Create a missing release; gh handles creating the tag if absent. An existing
  # tag is safe because its target was validated above.
  args=(release create "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY"
    --target "$RELEASE_TARGET" --title "${RELEASE_TITLE:-$RELEASE_TAG}")
  if [[ -n "${RELEASE_BODY:-}" ]]; then
    args+=(--notes "$RELEASE_BODY")
  elif [[ -n "${RELEASE_BODY_FILE:-}" ]]; then
    args+=(--notes-file "$RELEASE_BODY_FILE")
  else
    args+=(--generate-notes)
    if [[ -n "${NOTES_START_TAG:-}" ]]; then args+=(--notes-start-tag "$NOTES_START_TAG"); fi
  fi
  if [[ "$RELEASE_PRERELEASE" == true ]]; then args+=(--prerelease); fi
  if [[ "${RELEASE_DRAFT:-false}" == true ]]; then args+=(--draft); fi
  gh "${args[@]}"
  created=true
  release_json=$(gh api "repos/$RELEASE_REPOSITORY/releases/tags/$RELEASE_TAG")
fi

# Verify the actual remote tag, not just release.target_commitish (which can
# be a branch name or otherwise differ from the resolved commit).
git fetch --force --no-tags origin "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"
tagged_sha=$(git rev-parse "$RELEASE_TAG^{commit}")
if [[ "$tagged_sha" != "$RELEASE_TARGET" ]]; then
  echo "::error::Release tag $RELEASE_TAG points to $tagged_sha, expected $RELEASE_TARGET." >&2
  exit 1
fi

release_id=$(jq -er '.id' <<< "$release_json")
release_url=$(jq -er '.html_url' <<< "$release_json")
actual_tag=$(jq -er '.tag_name' <<< "$release_json")
[[ "$actual_tag" == "$RELEASE_TAG" ]] || { echo "::error::Release tag mismatch" >&2; exit 1; }

{
  echo "created=$created"
  echo "release-id=$release_id"
  echo "release-url=$release_url"
  echo "tag=$RELEASE_TAG"
} >> "$GITHUB_OUTPUT"
