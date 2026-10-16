# Publish to CurseForge

Upload an **existing** addon artifact to CurseForge. This action does not build, version, tag, or package anything.

The action uses the CurseForge author/upload API (`X-Api-Token`, not the public CFCore API) to resolve exact game-version names or slugs to numeric IDs, then sends a multipart upload. It rejects missing or ambiguous matches.

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

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `token` | Yes | CurseForge project upload token |
| `project-id` | Yes | Positive CurseForge project ID |
| `game` | Yes | Game endpoint slug, e.g. `wow` |
| `game-version` | Yes | Exact version name/slug, e.g. `12.1.5` |
| `game-version-type` | No | Version-type name, slug or numeric ID; disambiguates matching versions |
| `game-version-id` | No | Explicit numeric override; skips discovery |
| `file` | Yes | Non-empty local artifact path |
| `release-type` | Yes | `alpha`, `beta`, or `release` |
| `display-name` | No | Friendly published file name |
| `changelog` | No | Release notes text |
| `changelog-type` | No | `text`, `html`, or `markdown` (default) |
| `dry-run` | No | `true` resolves/validates without uploading |

## Outputs

- `game-version-id`: matched CurseForge version ID.
- `file-id`: new published file ID; empty during dry-run.

## Safety and responsibilities

- The action matches version names/slugs **exactly**, case-insensitively. A missing or ambiguous version is an error, not an opportunity to guess the latest.
- Callers decide whether to publish, manage release markers, and ensure idempotency. **Uploading is not intrinsically idempotent.** The action makes no automatic retries, because a network failure after server acceptance has an ambiguous outcome. Before retrying, callers should reconcile against CurseForge's published files.
- The action does not infer game version from TOC or artifact name, and does not derive WoW interface numbers.
- Python 3 is required on the runner; no external Python packages are required.
- `dry-run` still performs remote discovery unless an explicit version ID is supplied. It does not verify CurseForge project upload permissions.

## API reference

CurseForge's official [Upload API documentation](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-api) describes `/api/game/versions`, `/api/game/version-types`, and `/api/projects/{projectId}/upload-file`.
