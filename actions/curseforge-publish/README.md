# Publish to CurseForge

Upload an **existing** addon artifact to CurseForge. This action does not build, version, tag, or package anything.

The action uses the CurseForge author/upload API (`X-Api-Token`, not the public CFCore API) to resolve exact game-version names or slugs to numeric IDs, then sends a multipart upload. It rejects missing or ambiguous matches. Unlike WoW-only workflows, a published file can carry **multiple independent compatibility tags** (game version, loader, Java runtime, client/server environment, etc.).

## Example

```yaml
- name: Publish addon
  id: curseforge
  uses: Kralizek/github-actions/actions/curseforge-publish@v0.1.0
  with:
    token: ${{ secrets.CURSEFORGE_API_TOKEN }}
    project-id: ${{ vars.CURSEFORGE_PROJECT_ID }}
    game: wow
    game-version: '12.1.5'
    game-version-type: retail
    file: dist/my-addon.zip
    release-type: beta
    display-name: My Addon 1.0.0-beta.1
    changelog: 'Bug fixes and improvements'
    changelog-type: markdown
```

The example uses literal values for clarity. Replace them with your workflow's variables or matrix values as appropriate. The action must be released under an actual tag before using the shown version.

## Minecraft example: multiple compatibility dimensions

```yaml
- name: Publish Minecraft mod
  uses: Kralizek/github-actions/actions/curseforge-publish@v0.1.0
  with:
    token: ${{ secrets.CURSEFORGE_API_TOKEN }}
    project-id: ${{ vars.CURSEFORGE_PROJECT_ID }}
    game: minecraft
    game-versions: |
      [
        {"version":"1.21.1","type":"Minecraft 1.21"},
        {"version":"Fabric"},
        {"version":"Java 21"},
        {"version":"Server"}
      ]
    relations: '[{"slug":"fabric-api","type":"requiredDependency"}]'
    file: build/libs/example.jar
    release-type: beta
```

The example version tags and version-type labels are **illustrative** and must be checked against the target game's live CurseForge catalog. Each selector is resolved independently, exact matches are required, and duplicate IDs are removed. The singular `game-version` (with optional `game-version-type` or `game-version-id`) and plural `game-versions` inputs are **mutually exclusive**. The exact version type may differ between Minecraft releases; it is **not** necessarily a single stable `minecraft` type.

For optional child files:

```yaml
with:
  game: minecraft
  project-id: ${{ vars.CURSEFORGE_PROJECT_ID }}
  token: ${{ secrets.CURSEFORGE_API_TOKEN }}
  parent-file-id: ${{ steps.main.outputs.file-id }}
  file: build/libs/example-sources.jar
  release-type: beta
```

CurseForge does not permit the `gameVersions` field on a child file, so omit all version selectors for that case.

## Native version names (optional)

CurseForge also accepts `gameVersionNames` directly in upload metadata:

```yaml
- name: Publish with literal version names
  uses: Kralizek/github-actions/actions/curseforge-publish@v0.1.0
  with:
    token: ${{ secrets.CURSEFORGE_API_TOKEN }}
    project-id: ${{ vars.CURSEFORGE_PROJECT_ID }}
    game: minecraft
    game-version-names: '["Client","Server","26.1.2"]'
    file: dist/my-mod.jar
    release-type: beta
```

This bypasses version-ID discovery. **The upload API documents the field but does not document ambiguity handling for names shared across version types.** Prefer ID resolution (`game-version` or `game-versions`) when exact type identity is important. All three modes are mutually exclusive, and child uploads use none.

## Streaming and upload safety

Uploads use a streaming multipart body with an exact Content-Length. The action reads the artifact in 1 MiB chunks, not into memory all at once, and uses `application/octet-stream` so JARs and other file types work. The action does not automatically retry uncertain uploads; verify CurseForge publication state before retrying.

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `token` | Yes | CurseForge project upload token |
| `project-id` | Yes | Positive CurseForge project ID |
| `game` | Yes | Game endpoint slug, e.g. `wow` |
| `game-version` | Conditional | Optional primary exact version name/slug, e.g. `12.1.5` |
| `game-version-type` | No | Version-type name, slug or numeric ID; only valid with `game-version` |
| `game-versions` | No | Alternative full JSON array of selectors: strings or `{version,type}` / `{id}` objects |
| `game-version-names` | No | Alternative direct JSON array of literal names, sent without discovery |
| `relations` | No | JSON array of `{slug/projectID,type}` project relationships |
| `parent-file-id` | No | Positive parent file ID for child uploads (must omit version selectors) |
| `manual-release` | No | If `true`, hold file for manual release after approval |
| `game-version-id` | No | Alternative explicit numeric ID for the singular mode; cannot be combined with `game-version` or `game-version-type` |
| `file` | Yes | Non-empty local artifact path |
| `release-type` | Yes | `alpha`, `beta`, or `release` |
| `display-name` | No | Friendly published file name |
| `changelog` | No | Release notes text |
| `changelog-type` | No | `text`, `html`, or `markdown` (default) |
| `dry-run` | No | `true` resolves/validates without uploading |

## Outputs

The `game-versions` output is always a JSON array of **flat version objects**. It retains the input `version` and `type` fields where supplied, and adds the numeric `versionId` for resolved or explicitly supplied IDs.

For example, resolving two version selectors yields:

```json
[
  {"version":"12.1.5","type":"retail","versionId":16984},
  {"version":"1.60.1","type":"classic","versionId":17053}
]
```

Native `game-version-names` inputs do not resolve IDs:

```json
[
  {"version":"Client"},
  {"version":"Server"}
]
```

An explicit ID without a name produces `{"versionId":16984}`. Selectors that specify a numeric ID cannot also specify `version` or `type`: conflicting fields are rejected before upload. Output entries retain their input order and identity, including entries that resolve to the same ID; only the IDs sent to CurseForge are deduplicated. Child-file uploads return `[]`. Dry runs produce the same version array as normal uploads.

- `game-versions`: flat JSON array with optional `version`, optional `type`, and `versionId` when available.
- `file-id`: published CurseForge file ID; empty for dry runs.

## Safety and responsibilities

- A standalone upload needs at least one version selector. Use exactly one mode: singular `game-version` inputs, resolved `game-versions`, or direct `game-version-names`. Use `game-versions` for Minecraft-style multi-tag uploads. A child file instead needs `parent-file-id` and must omit all version selectors.
- The action matches version names/slugs **exactly**, case-insensitively. A missing or ambiguous version is an error, not an opportunity to guess the latest.
- Callers decide whether to publish, manage release markers, and ensure idempotency. **Uploading is not intrinsically idempotent.** The action makes no automatic retries, because a network failure after server acceptance has an ambiguous outcome. Before retrying, callers should reconcile against CurseForge's published files.
- The action does not infer game version from TOC or artifact name, and does not derive WoW interface numbers.
- Python 3.8+ is required on the runner; no external Python packages are required.
- `dry-run` still performs remote discovery unless an explicit version ID is supplied. It does not verify CurseForge project upload permissions.

## API reference

CurseForge's official [Upload API documentation](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-api) describes `/api/game/versions`, `/api/game/version-types`, and `/api/projects/{projectId}/upload-file`.
