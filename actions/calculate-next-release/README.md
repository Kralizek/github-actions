# Calculate next release

Calculates the next stable Semantic Versioning release from the repository's Git tags.

The action finds the highest stable tag matching the configured prefix and `major.minor.patch`, applies the requested bump, and returns the resulting version and tag. Prerelease tags are ignored.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `bump` | Yes | | Version component to increment: `patch`, `minor`, or `major`. |
| `tag-prefix` | No | `v` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `version` | Calculated SemVer version without the tag prefix. |
| `tag` | Calculated release tag including the configured prefix. |
| `previous-tag` | Latest stable release tag used as the calculation baseline. |

A full Git checkout is required so the action can inspect release tags locally.
