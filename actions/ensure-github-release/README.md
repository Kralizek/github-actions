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
```

The action reference is illustrative; use a published version or commit SHA.

## Behavior

* Missing release: creates it, optionally creating the tag, and generates notes.
* Existing release: preserves its metadata and returns its identity.
* Existing tag pointing to another commit: fails without moving the tag.
* API lookup errors other than a verified HTTP 404: fail closed.
* Verifies the tag's resolved commit after creation/reuse.

Outputs are `created` (`true`/`false`), `release-id`,
`release-url`, and `tag`.

This action does **not** upload assets, edit an existing release, or deduplicate
publication to external services. Callers should serialize competing release
operations for the same tag.
