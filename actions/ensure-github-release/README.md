# Ensure GitHub release

Creates or reuses a GitHub release for a selected tag and **exact commit**.
This action complements `calculate-next-version`: version calculation chooses
the release identity, while this action ensures GitHub contains that release.

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
  - id: version
    uses: Kralizek/github-actions/actions/calculate-next-version@v0.4
    with:
      bump: patch
  - id: release
    uses: Kralizek/github-actions/actions/ensure-github-release@v0.5
    with:
      tag: ${{ steps.version.outputs.tag }}
      target: ${{ github.sha }}
      prerelease: ${{ steps.version.outputs.prerelease }}
      release-notes-start-tag: ${{ steps.version.outputs.release-notes-start-tag }}
```

The version in this example is illustrative; update it after the action is released.

## Behavior

* Missing release: creates it, optionally creating the tag, and generates notes.
* Existing release: preserves its metadata and returns its identity.
* Existing tag pointing to another commit: fails without moving the tag.
* API lookup errors other than a verified HTTP 404: fail closed.
* Verifies the tag's resolved commit after creation/reuse.

Outputs are `created` (`true`/`false`), `release-id`,
`release-url`, and `tag`.

This action does **not** upload assets, edit an existing release, or deduplicate
publication to registries such as NuGet or CurseForge. It assumes callers serialize
competing release operations for the same tag.
