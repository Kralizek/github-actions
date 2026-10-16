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
    game-version: ${{ matrix.version }}
    game-version-type: ${{ matrix.metadata.curseforge.versionType || matrix.id }}
    file: authoritative/${{ matrix.asset }}
    release-type: ${{ inputs.channel == 'stable' && 'release' || inputs.channel }}
    display-name: Artisan Logbook ${{ needs.release.outputs.version }} (${{ matrix.id }})
    changelog: ${{ steps.authoritative.outputs.notes }}
    changelog-type: markdown
```

The above is an **illustrative future consumer**: the action must first be released under an actual tag. Your own matrix structure is caller-owned. For a flavor config, default the provider's version type to the flavor ID unless overridden; do not hardcode CurseForge IDs in source control.

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

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `token` | Yes | CurseForge project upload token |
| `project-id` | Yes | Positive CurseForge project ID |
| `game` | Yes | Game endpoint slug, e.g. `wow` |
| `game-version` | Conditional | Optional primary exact version name/slug, e.g. `12.1.5` |
| `game-version-type` | No | Version-type name, slug or numeric ID; disambiguates the primary version |
| `game-versions` | No | JSON array of additional selectors: strings or `{version,type}` / `{id}` objects |
| `relations` | No | JSON array of `{slug/projectID,type}` project relationships |
| `parent-file-id` | No | Positive parent file ID for child uploads (must omit version selectors) |
| `manual-release` | No | If `true`, hold file for manual release after approval |
| `game-version-id` | No | Explicit numeric override; skips discovery |
| `file` | Yes | Non-empty local artifact path |
| `release-type` | Yes | `alpha`, `beta`, or `release` |
| `display-name` | No | Friendly published file name |
| `changelog` | No | Release notes text |
| `changelog-type` | No | `text`, `html`, or `markdown` (default) |
| `dry-run` | No | `true` resolves/validates without uploading |

## Outputs

- `game-version-id`: first matched CurseForge version ID (for single-version callers).\n- `game-version-ids`: all resolved CurseForge version IDs, comma-separated.
- `file-id`: new published file ID; empty during dry-run.

## Safety and responsibilities

- A standalone upload needs at least one version selector. Use either the singular inputs or `game-versions`, never both. Use `game-versions` for Minecraft-style multi-tag uploads. A child file instead needs `parent-file-id` and must omit all version selectors.\n- The action matches version names/slugs **exactly**, case-insensitively. A missing or ambiguous version is an error, not an opportunity to guess the latest.
- Callers decide whether to publish, manage release markers, and ensure idempotency. **Uploading is not intrinsically idempotent.** The action makes no automatic retries, because a network failure after server acceptance has an ambiguous outcome. Before retrying, callers should reconcile against CurseForge's published files.
- The action does not infer game version from TOC or artifact name, and does not derive WoW interface numbers.
- Python 3 is required on the runner; no external Python packages are required.
- `dry-run` still performs remote discovery unless an explicit version ID is supplied. It does not verify CurseForge project upload permissions.

## API reference

CurseForge's official [Upload API documentation](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-api) describes `/api/game/versions`, `/api/game/version-types`, and `/api/projects/{projectId}/upload-file`.
