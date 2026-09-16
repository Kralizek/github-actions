# Calculate next version

Calculates the next stable or prerelease Semantic Versioning version from the repository's Git tags.

The action finds the highest stable tag matching the configured prefix and `major.minor.patch`, applies the requested bump, and returns the resulting version and tag. Existing prerelease tags do not affect the stable baseline.

If no stable release tag exists yet, the action bootstraps at `0.1.0`. When `minimum-version` is provided, it replaces that bootstrap target and also acts as a floor for later releases. The requested bump is only applied once a stable baseline exists, so `patch`, `minor`, and `major` all produce the same bootstrap target when the repository has no stable release yet.

When `channel` is provided, the calculated stable target becomes the prerelease base and the action selects the next numeric sequence for that channel. For example, with `v1.2.3` as the latest stable release, `bump: minor` and `channel: rc` produces `v1.3.0-rc.1`. If `v1.3.0-rc.1` already exists on another commit, the next result is `v1.3.0-rc.2`.

An explicit `version` can be supplied to bypass derived version calculation. Stable overrides must use `major.minor.patch` and cannot be lower than the latest stable release. Prerelease overrides must match the selected channel and use `major.minor.patch-channel.number`. Explicit versions override calculation only: release policy still applies, including stable-version monotonicity, prerelease stable closure, and monotonic channel progression. If the resulting tag already exists on `HEAD`, the action reuses it; if it points to a different commit, the action fails.

Release retries are operation-specific. For stable releases, the action derives the requested target from release history without treating stable tags on `HEAD` as the previous release. If that exact calculated target already tags `HEAD`, it is reused. A different stable tag on `HEAD` does not suppress the requested bump and remains part of the normal release baseline. For prereleases, rerunning the same base-version/channel operation reuses the matching tag already on `HEAD` instead of incrementing the sequence again.

If multiple stable release tags point to `HEAD`, or multiple matching prerelease tags for the same base version and channel point to `HEAD`, the action fails rather than choosing one arbitrarily.

Prerelease channels progress monotonically across the repository for each base version. The action considers all prerelease tags for that base version and rejects any new channel that sorts lexicographically before the highest channel already used. For example, after `v1.3.0-rc.1` exists anywhere, a new `beta` prerelease for `1.3.0` is rejected, while another `rc` or a later channel remains valid. An exact existing tag on `HEAD` may still be reused as an idempotent retry.

A stable release may be created from a commit that already has prerelease tags. A stable tag closes only its own base version: once `v1.3.0` exists, `v1.3.0-*` prereleases are no longer valid targets, including explicit overrides, but the same commit may still be used for a later base such as `v1.4.0-rc.1` if that is what the current stable baseline and requested bump calculate.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `bump` | Yes | | Version component to increment after an existing stable release: `patch`, `minor`, or `major`. |
| `channel` | No | empty | Optional prerelease channel such as `alpha`, `beta`, or `rc`. Any valid single SemVer prerelease identifier is accepted. |
| `version` | No | empty | Optional explicit SemVer version override. Stable versions use `major.minor.patch` and cannot move backward from the latest stable release; prereleases must match `channel` and use `major.minor.patch-channel.number`. |
| `minimum-version` | No | empty | Optional stable SemVer floor. It also replaces the default `0.1.0` bootstrap target when no stable tag exists yet. |
| `tag-prefix` | No | `v` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `version` | Calculated, explicitly selected, or reused SemVer version without the tag prefix. |
| `tag` | Calculated, explicitly selected, or reused release tag including the configured prefix. |
| `previous-tag` | Stable release tag used as the calculation baseline, or empty during bootstrap. |
| `base-version` | Stable target before any prerelease channel is applied. |
| `prerelease` | `true` when `channel` is provided, otherwise `false`. |
| `channel` | Prerelease channel used for the result, or empty for a stable release. |

Stable release tags, explicit stable versions, and `minimum-version` use strict SemVer numeric components: leading zeroes are rejected. Explicit prerelease sequence numbers also reject leading zeroes. A full Git checkout is required so the action can inspect release tags locally.
