# Calculate next release

Calculates the next stable or prerelease Semantic Versioning release from the repository's Git tags.

The action finds the highest stable tag matching the configured prefix and `major.minor.patch`, applies the requested bump, and returns the resulting version and tag. Existing prerelease tags do not affect the stable baseline.

When `minimum-version` is provided, the calculated stable target is raised to that version when the normal bump would produce a lower version. If no stable release tag exists yet, `minimum-version` becomes the bootstrap target directly; the requested bump is only applied once a stable baseline exists.

When `channel` is provided, the calculated stable target becomes the prerelease base and the action selects the next numeric sequence for that channel. For example, with `v1.2.3` as the latest stable release, `bump: minor` and `channel: rc` produces `v1.3.0-rc.1`. If `v1.3.0-rc.1` already exists, the next result is `v1.3.0-rc.2`.

Changing channels keeps the same stable target. If `v1.3.0-beta.2` exists, asking for `bump: minor` and `channel: rc` produces `v1.3.0-rc.1`.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `bump` | Yes | | Version component to increment: `patch`, `minor`, or `major`. Applied after an existing stable release. |
| `channel` | No | empty | Optional prerelease channel such as `alpha`, `beta`, or `rc`. Any valid single SemVer prerelease identifier is accepted. |
| `minimum-version` | No | empty | Optional stable SemVer floor and bootstrap target when no stable tag exists yet. |
| `tag-prefix` | No | `v` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `version` | Calculated SemVer version without the tag prefix. |
| `tag` | Calculated release tag including the configured prefix. |
| `previous-tag` | Latest stable release tag used as the calculation baseline, or empty during bootstrap. |
| `base-version` | Stable target before any prerelease channel is applied. |
| `prerelease` | `true` when `channel` is provided, otherwise `false`. |
| `channel` | Prerelease channel used for the result, or empty for a stable release. |

Stable release tags and `minimum-version` use strict SemVer numeric components: leading zeroes are rejected. A full Git checkout is required so the action can inspect release tags locally.
