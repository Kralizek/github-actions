# Calculate next release

Calculates the next stable or prerelease Semantic Versioning release from the repository's Git tags.

The action finds the highest stable tag matching the configured prefix and `major.minor.patch`, applies the requested bump, and returns the resulting version and tag. Existing prerelease tags do not affect the stable baseline.

If no stable release tag exists yet, the action bootstraps at `0.1.0`. When `minimum-version` is provided, it replaces that bootstrap target and also acts as a floor for later releases. The requested bump is only applied once a stable baseline exists, so `patch`, `minor`, and `major` all produce the same bootstrap target when the repository has no stable release yet.

When `channel` is provided, the calculated stable target becomes the prerelease base and the action selects the next numeric sequence for that channel. For example, with `v1.2.3` as the latest stable release, `bump: minor` and `channel: rc` produces `v1.3.0-rc.1`. If `v1.3.0-rc.1` already exists on another commit, the next result is `v1.3.0-rc.2`.

Rerunning the same prerelease operation on a commit that already has exactly one matching tag for the calculated base version and requested channel reuses that tag. Tags for other channels on the same commit are ignored, so a commit may legitimately move from `alpha` to `beta` to `rc`. If multiple matching tags for the same base version and channel point to `HEAD`, the action fails rather than choosing one arbitrarily.

Changing channels keeps the same stable target. If `v1.3.0-beta.2` exists, asking for `bump: minor` and `channel: rc` produces `v1.3.0-rc.1`.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `bump` | Yes | | Version component to increment after an existing stable release: `patch`, `minor`, or `major`. |
| `channel` | No | empty | Optional prerelease channel such as `alpha`, `beta`, or `rc`. Any valid single SemVer prerelease identifier is accepted. |
| `minimum-version` | No | empty | Optional stable SemVer floor. It also replaces the default `0.1.0` bootstrap target when no stable tag exists yet. |
| `tag-prefix` | No | `v` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `version` | Calculated or reused SemVer version without the tag prefix. |
| `tag` | Calculated or reused release tag including the configured prefix. |
| `previous-tag` | Latest stable release tag used as the calculation baseline, or empty during bootstrap. |
| `base-version` | Stable target before any prerelease channel is applied. |
| `prerelease` | `true` when `channel` is provided, otherwise `false`. |
| `channel` | Prerelease channel used for the result, or empty for a stable release. |

Stable release tags and `minimum-version` use strict SemVer numeric components: leading zeroes are rejected. A full Git checkout is required so the action can inspect release tags locally.
