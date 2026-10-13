# Ensure GitHub release

Creates or reuses a GitHub release for a selected tag and **exact commit**.
The caller supplies the release identity and expected commit. The action verifies
that the tag identifies that commit before returning the release details.

Requires checkout with Git history/tags, `gh`, `git`, `jq`, a token with
`contents: write` permission, and network access to the repository remote.
The caller remains responsible for packaging and attaching assets.

## Example

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
  - id: release
    uses: Kralizek/github-actions/actions/ensure-github-release@v0.5
    with:
      tag: v1.2.3
      target: ${{ github.sha }}
      prerelease: 'false'
      draft: 'true' # Optional; defaults to false
```

The action reference is illustrative; use a published version or commit SHA.

## Release notes

By default, the action generates release notes. Supply `body` for Markdown text or
`body-file` for a path to an existing Markdown file. These inputs are mutually
exclusive and cannot be combined with `release-notes-start-tag`, which applies
only when generating notes. Existing releases retain their current notes.

## Behavior

* Missing release: creates it, optionally creating the tag, using explicit or generated notes. By default the release is published; `draft: 'true'` creates a draft.
* Existing release: preserves its metadata (including the draft/published state) and returns its identity. The `draft` input applies only on creation.
* Existing tag pointing to another commit: fails without moving the tag.
* API lookup errors other than a verified HTTP 404: fail closed.
* Verifies the tag's resolved commit after creation/reuse.

Outputs are `created` (`true`/`false`), `release-id`,
`release-url`, and `tag`.

This action does **not** upload assets, edit an existing release, or deduplicate
publication to external services. Callers should serialize competing release
operations for the same tag.
