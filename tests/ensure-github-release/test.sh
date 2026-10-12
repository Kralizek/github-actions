#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/actions/ensure-github-release/ensure.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git init -q --bare "$work/remote.git"
git init -q "$work/repo"
cd "$work/repo"
git config user.name Validation
git config user.email validation@example.invalid
git remote add origin "$work/remote.git"
echo start > file
git add file
git commit -qm start
head_sha=$(git rev-parse HEAD)
git push -q origin HEAD:refs/heads/master

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "api --include")
    case "${MOCK_API_MODE:-missing}" in
      missing)
        printf 'HTTP/2.0 404 Not Found\n\n{"message":"Not Found"}\n'
        exit 1 ;;
      failure)
        printf 'HTTP/2.0 503 Service Unavailable\n\n{"message":"Unavailable"}\n'
        exit 1 ;;
      found)
        printf 'HTTP/2.0 200 OK\n\n{"id":42,"html_url":"https://github.com/example/repo/releases/tag/v0.1.0","tag_name":"v0.1.0"}\n'
        exit 0 ;;
    esac ;;
  "release create")
    echo created >> "$MOCK_EVENTS"
    printf '%s\\n' "$@" > "$MOCK_ARGS"
    git tag v0.1.0 "$RELEASE_TARGET"
    git push -q origin refs/tags/v0.1.0
    exit 0 ;;
  "api repos/example/repo/releases/tags/v0.1.0")
    printf '{"id":42,"html_url":"https://github.com/example/repo/releases/tag/v0.1.0","tag_name":"v0.1.0"}\n'
    exit 0 ;;
esac
echo "unexpected gh call: $*" >&2
exit 2
GH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
export GH_TOKEN=fake RELEASE_REPOSITORY=example/repo RELEASE_TAG=v0.1.0
export RELEASE_TARGET="$head_sha" RELEASE_TITLE=v0.1.0 RELEASE_PRERELEASE=false
export NOTES_START_TAG='' RELEASE_BODY='' RELEASE_BODY_FILE='' MOCK_EVENTS="$work/events" MOCK_ARGS="$work/args"

run_case() {
  export GITHUB_OUTPUT="$work/output"
  : > "$GITHUB_OUTPUT"
  bash "$script"
}

echo "Creates missing tag and release"
export MOCK_API_MODE=missing
run_case
grep -qx 'created=true' "$GITHUB_OUTPUT"
grep -qx 'release-id=42' "$GITHUB_OUTPUT"
grep -qx 'tag=v0.1.0' "$GITHUB_OUTPUT"
test "$(wc -l < "$MOCK_EVENTS")" -eq 1

echo "Reuses existing release and tag"
export MOCK_API_MODE=found
run_case
grep -qx 'created=false' "$GITHUB_OUTPUT"
test "$(wc -l < "$MOCK_EVENTS")" -eq 1

echo "Fails closed on transient API error"
export MOCK_API_MODE=failure
if run_case >/dev/null 2>&1; then
  echo "Expected a transient API error to fail" >&2
  exit 1
fi
test "$(wc -l < "$MOCK_EVENTS")" -eq 1

echo "Rejects a release tag on another commit"
echo later >> file
git add file
git commit -qm later
export RELEASE_TARGET="$(git rev-parse HEAD)" MOCK_API_MODE=found
if run_case >/dev/null 2>&1; then
  echo "Expected conflicting tag to fail" >&2
  exit 1
fi
test "$(wc -l < "$MOCK_EVENTS")" -eq 1


echo "Explicit body on a new release"
set -x
git tag -d v0.1.0 >/dev/null
git push -q origin :refs/tags/v0.1.0
export RELEASE_TARGET="$(git rev-parse HEAD)" MOCK_API_MODE=missing RELEASE_BODY='Custom **Markdown** notes'
run_case
grep -qx -- '--notes' "$MOCK_ARGS"
grep -Fxq -- 'Custom **Markdown** notes' "$MOCK_ARGS"
if grep -qx -- '--generate-notes' "$MOCK_ARGS"; then exit 1; fi

echo "Explicit notes file on a new release"
git tag -d v0.1.0 >/dev/null
git push -q origin :refs/tags/v0.1.0
printf 'File notes\n' > "$work/notes.md"
export RELEASE_BODY='' RELEASE_BODY_FILE="$work/notes.md"
run_case
grep -qx -- '--notes-file' "$MOCK_ARGS"
grep -Fxq -- "$work/notes.md" "$MOCK_ARGS"

echo "Reject both explicit note inputs"
export RELEASE_BODY='text'
if run_case >/dev/null 2>&1; then echo 'Expected both inputs to fail' >&2; exit 1; fi

echo "Reject notes baseline with explicit body"
export RELEASE_BODY_FILE='' NOTES_START_TAG='v0.0.1'
if run_case >/dev/null 2>&1; then echo 'Expected notes baseline conflict to fail' >&2; exit 1; fi

echo "Reject nonexistent notes file"
export RELEASE_BODY='' NOTES_START_TAG='' RELEASE_BODY_FILE="$work/missing.md"
if run_case >/dev/null 2>&1; then echo 'Expected missing notes file to fail' >&2; exit 1; fi

echo "ensure-github-release tests passed"
