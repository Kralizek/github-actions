# Calculate next release

Calculates the next repository release identifier independently of package/version semantics.

The default `periodic` scheme combines a calendar period with a sequence number. With the default inputs (`period: month` and the default format `r{date:%Y%m}-{sequence:4}`), releases use the EduConvert-compatible form `rYYYYMM-NNNN`. For example, after `r202609-0004`, another release in September 2026 produces `r202609-0005`; the first release in October produces `r202610-0001`.

`period` controls when the sequence resets. `format` controls only rendering. Supported periods are `year`, `month`, `week`, and `day`, with these defaults:

| Period | Default format | Example |
|---|---|---|
| `year` | `r{date:%Y}-{sequence:4}` | `r2026-0001` |
| `month` | `r{date:%Y%m}-{sequence:4}` | `r202609-0001` |
| `week` | `r{date:%G%V}-{sequence:4}` | `r202638-0001` |
| `day` | `r{date:%Y%m%d}-{sequence:4}` | `r20260916-0001` |

## Format grammar

A format contains exactly one date token and one sequence token:

```text
{date:<date-format>}
{sequence:<digits>}
```

Everything outside those tokens is literal text. For example:

```text
r{date:%Y-%m}-{sequence:6}
```

renders as `r2026-09-000001`.

The sequence width must be between 1 and 9. The date format supports `%Y`, `%m`, `%d`, `%G`, and `%V`. The selected `period` determines which date components are required:

- `year`: `%Y`
- `month`: `%Y` and `%m`
- `week`: `%G` and `%V`
- `day`: `%Y`, `%m`, and `%d`

Those tokens may be rendered in any order. Historical tags are parsed back into semantic period and sequence values, so release ordering does not depend on lexicographic tag order. For example, `{sequence:3}-r{date:%Y%m}` is valid.

The action reads Git tags directly rather than GitHub Release objects. Tags that do not match the configured format are ignored. A full Git checkout is required.

Periodic releases are globally monotonic. If the latest matching release belongs to a later period than the current UTC period, calculation fails rather than moving backwards. Reruns are idempotent only when `HEAD` already owns the latest matching release tag for the current period; an older release tag on `HEAD` is not reused after a later release exists elsewhere.

`scheme` is part of the public contract so other release-identifier strategies can be added later without changing the action path. `periodic` is currently the only supported value.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `scheme` | No | `periodic` | Release identifier scheme. Currently only `periodic` is supported. |
| `period` | No | `month` | Sequence reset boundary: `year`, `month`, `week`, or `day`. |
| `format` | No | period-specific | Release rendering format containing exactly one `{date:...}` token and one `{sequence:N}` token. |

## Outputs

| Output | Description |
|---|---|
| `release` | Calculated or reused release identifier. |
| `tag` | Alias of `release`, suitable for Git tagging/release creation. |
| `previous-tag` | Previous matching release tag, or empty for the first release. On an idempotent rerun this is the release preceding the reused tag. |
| `scheme` | Scheme used to calculate the release. |
| `period` | Rendered date portion for the current period. |
| `sequence` | Zero-padded sequence within the current period. |

The periodic scheme uses the runner's UTC date. The implementation accepts an internal `RELEASE_DATE=YYYY-MM-DD` environment override for deterministic tests; this is not an action input.

The action is a composite action that installs the current Deno 2.x release with `denoland/setup-deno` and runs the single `index.ts` entrypoint directly. There is no Node runtime declaration, package installation, transpilation step, or checked-in generated JavaScript artifact. Following Deno 2.x runtime updates therefore does not require publishing a new version of this action.
