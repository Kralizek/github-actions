#!/usr/bin/env bash
set -euo pipefail

case "$SCHEME" in
  calendar)
    ;;
  *)
    echo "Unsupported release scheme: $SCHEME" >&2
    exit 1
    ;;
esac

period="${CALENDAR_PERIOD:-$(date -u +%Y%m)}"
if [[ ! "$period" =~ ^[0-9]{4}(0[1-9]|1[0-2])$ ]]; then
  echo "Calendar period must use YYYYMM with a valid month: $period" >&2
  exit 1
fi

escaped_prefix=$(printf '%s' "$TAG_PREFIX" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
tag_pattern="^${escaped_prefix}([0-9]{4}(0[1-9]|1[0-2]))-([0-9]{4})$"

valid_tag() {
  local tag="$1"
  if [[ ! "$tag" =~ $tag_pattern ]]; then
    return 1
  fi

  local sequence="${BASH_REMATCH[3]}"
  (( 10#$sequence > 0 ))
}

mapfile -t all_tags < <(
  while IFS= read -r tag; do
    if valid_tag "$tag"; then
      printf '%s\n' "$tag"
    fi
  done < <(git tag -l "${TAG_PREFIX}[0-9]*-[0-9]*") | sort
)

latest_tag=''
if (( ${#all_tags[@]} > 0 )); then
  latest_tag="${all_tags[-1]}"
fi

head_commit=$(git rev-parse HEAD)
mapfile -t current_period_tags < <(
  while IFS= read -r tag; do
    if valid_tag "$tag"; then
      suffix="${tag#"$TAG_PREFIX"}"
      tag_period="${suffix%-*}"
      if [ "$tag_period" = "$period" ]; then
        printf '%s\n' "$tag"
      fi
    fi
  done < <(git tag --points-at HEAD -l "${TAG_PREFIX}${period}-*") | sort
)

if (( ${#current_period_tags[@]} > 1 )); then
  echo "Multiple calendar release tags for $period point to HEAD: ${current_period_tags[*]}" >&2
  exit 1
fi

find_previous_tag_excluding_head() {
  local tag tag_commit previous=''
  for tag in "${all_tags[@]}"; do
    tag_commit=$(git rev-list -n 1 "$tag")
    if [ "$tag_commit" != "$head_commit" ]; then
      previous="$tag"
    fi
  done
  printf '%s\n' "$previous"
}

previous_tag="$latest_tag"
reused=false

if (( ${#current_period_tags[@]} == 1 )); then
  tag="${current_period_tags[0]}"
  if [ "$tag" != "$latest_tag" ]; then
    echo "Cannot reuse $tag because latest calendar release is $latest_tag." >&2
    exit 1
  fi

  reused=true
  previous_tag=$(find_previous_tag_excluding_head)
  release="${tag#"$TAG_PREFIX"}"
  sequence="${release#*-}"
else
  if [ -n "$latest_tag" ]; then
    latest_release="${latest_tag#"$TAG_PREFIX"}"
    latest_period="${latest_release%-*}"
    latest_sequence="${latest_release#*-}"

    if [[ "$latest_period" > "$period" ]]; then
      echo "Cannot move calendar release period backwards from $latest_period to $period." >&2
      exit 1
    fi

    if [ "$latest_period" = "$period" ]; then
      next_sequence=$((10#$latest_sequence + 1))
    else
      next_sequence=1
    fi
  else
    next_sequence=1
  fi

  if (( next_sequence > 9999 )); then
    echo "Calendar release sequence exhausted for $period." >&2
    exit 1
  fi

  sequence=$(printf '%04d' "$next_sequence")
  release="${period}-${sequence}"
  tag="${TAG_PREFIX}${release}"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "Tag $tag already exists unexpectedly." >&2
    exit 1
  fi
fi

if [ "$reused" = true ]; then
  echo "Reusing release tag on HEAD: $tag"
else
  echo "Next release: $tag"
fi

echo "release=$release" >> "$GITHUB_OUTPUT"
echo "tag=$tag" >> "$GITHUB_OUTPUT"
echo "previous-tag=$previous_tag" >> "$GITHUB_OUTPUT"
echo "scheme=$SCHEME" >> "$GITHUB_OUTPUT"
echo "period=$period" >> "$GITHUB_OUTPUT"
echo "sequence=$sequence" >> "$GITHUB_OUTPUT"
