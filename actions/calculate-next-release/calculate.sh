#!/usr/bin/env bash
set -euo pipefail

case "$SCHEME" in
  periodic)
    ;;
  *)
    echo "Unsupported release scheme: $SCHEME" >&2
    exit 1
    ;;
esac

case "$PERIOD" in
  year)
    default_period_format='%Y'
    ;;
  month)
    default_period_format='%Y%m'
    ;;
  week)
    default_period_format='%G%V'
    ;;
  day)
    default_period_format='%Y%m%d'
    ;;
  *)
    echo "Unsupported period: $PERIOD" >&2
    exit 1
    ;;
esac

period_format="${PERIOD_FORMAT:-$default_period_format}"

validate_period_format() {
  local format="$1"
  local stripped="$format"

  stripped="${stripped//%Y/}"
  stripped="${stripped//%m/}"
  stripped="${stripped//%d/}"
  stripped="${stripped//%G/}"
  stripped="${stripped//%V/}"

  if [[ "$stripped" == *%* ]]; then
    echo "Unsupported token in period format: $format" >&2
    exit 1
  fi

  case "$PERIOD" in
    year)
      [[ "$format" == *%Y* ]] || { echo "Year period format must contain %Y." >&2; exit 1; }
      [[ "$format" != *%m* && "$format" != *%d* && "$format" != *%G* && "$format" != *%V* ]] || {
        echo "Year period format cannot contain finer-grained date tokens." >&2
        exit 1
      }
      ;;
    month)
      [[ "$format" == *%Y*%m* ]] || {
        echo "Month period format must contain %Y before %m so labels sort chronologically." >&2
        exit 1
      }
      [[ "$format" != *%d* && "$format" != *%G* && "$format" != *%V* ]] || {
        echo "Month period format cannot contain day or week tokens." >&2
        exit 1
      }
      ;;
    week)
      [[ "$format" == *%G*%V* ]] || {
        echo "Week period format must contain %G before %V so labels sort chronologically." >&2
        exit 1
      }
      [[ "$format" != *%Y* && "$format" != *%m* && "$format" != *%d* ]] || {
        echo "Week period format must use ISO week-year/week tokens only." >&2
        exit 1
      }
      ;;
    day)
      [[ "$format" == *%Y*%m*%d* ]] || {
        echo "Day period format must contain %Y, %m, and %d in chronological order." >&2
        exit 1
      }
      [[ "$format" != *%G* && "$format" != *%V* ]] || {
        echo "Day period format cannot contain week tokens." >&2
        exit 1
      }
      ;;
  esac
}

validate_period_format "$period_format"

if [[ ! "$DIGITS" =~ ^[1-9]$ ]]; then
  echo "digits must be an integer between 1 and 9: $DIGITS" >&2
  exit 1
fi

period="${PERIOD_VALUE:-$(date -u +"$period_format")}"

escaped_format=$(printf '%s' "$period_format" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
period_regex="$escaped_format"
period_regex="${period_regex//%Y/[0-9]{4}}"
period_regex="${period_regex//%G/[0-9]{4}}"
period_regex="${period_regex//%m/(0[1-9]|1[0-2])}"
period_regex="${period_regex//%d/(0[1-9]|[12][0-9]|3[01])}"
period_regex="${period_regex//%V/(0[1-9]|[1-4][0-9]|5[0-3])}"

if [[ ! "$period" =~ ^${period_regex}$ ]]; then
  echo "Rendered period '$period' does not match period format '$period_format'." >&2
  exit 1
fi

escaped_prefix=$(printf '%s' "$TAG_PREFIX" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
tag_pattern="^${escaped_prefix}(${period_regex})-[0-9]{${DIGITS}}$"

valid_tag() {
  local tag="$1"
  if [[ ! "$tag" =~ $tag_pattern ]]; then
    return 1
  fi

  local sequence="${tag##*-}"
  (( 10#$sequence > 0 ))
}

mapfile -t all_tags < <(
  while IFS= read -r tag; do
    if valid_tag "$tag"; then
      printf '%s\n' "$tag"
    fi
  done < <(git tag -l "${TAG_PREFIX}*-*") | sort
)

latest_tag=''
if (( ${#all_tags[@]} > 0 )); then
  latest_tag="${all_tags[-1]}"
fi

head_commit=$(git rev-parse HEAD)
mapfile -t current_period_tags < <(
  while IFS= read -r tag; do
    if valid_tag "$tag"; then
      printf '%s\n' "$tag"
    fi
  done < <(git tag --points-at HEAD -l "${TAG_PREFIX}${period}-*") | sort
)

if (( ${#current_period_tags[@]} > 1 )); then
  echo "Multiple periodic release tags for $period point to HEAD: ${current_period_tags[*]}" >&2
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
    echo "Cannot reuse $tag because latest periodic release is $latest_tag." >&2
    exit 1
  fi

  reused=true
  previous_tag=$(find_previous_tag_excluding_head)
  release="${tag#"$TAG_PREFIX"}"
  sequence="${release##*-}"
else
  if [ -n "$latest_tag" ]; then
    latest_release="${latest_tag#"$TAG_PREFIX"}"
    latest_period="${latest_release%-*}"
    latest_sequence="${latest_release##*-}"

    if [[ "$latest_period" > "$period" ]]; then
      echo "Cannot move periodic release period backwards from $latest_period to $period." >&2
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

  max_sequence=$((10 ** DIGITS - 1))
  if (( next_sequence > max_sequence )); then
    echo "Periodic release sequence exhausted for $period with $DIGITS digits." >&2
    exit 1
  fi

  sequence=$(printf "%0${DIGITS}d" "$next_sequence")
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
