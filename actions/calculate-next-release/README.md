# Calculate next release

Calculates the next repository release identifier independently of package/version semantics.

The default `periodic` scheme combines a calendar period label with a zero-padded sequence. With the default inputs (`period: month`, default period format `%Y%m`, `digits: 4`, `tag-prefix: r`), releases use the EduConvert-compatible form `rYYYYMM-NNNN`. For example, after `r202609-0004`, another release in September 2026 produces `r202609-0005`; the first release in October produces `r202610-0001`.

The period boundary and its display format are separate concepts. `period` controls when the sequence resets; `period-format` controls how that period is rendered in the tag. Supported periods are `year`, `month`, `week`, and `day`. Their default formats are `%Y`, `%Y%m`, `%G%V`, and `%Y%m%d` respectively. Formats may add literal separators, for example `%Y-%m` or `%G-W%V`, but the date components must remain ordered from coarse to fine so lexicographic tag order remains chronological.

The action reads Git tags directly rather than GitHub Release objects. Malformed tags are ignored. A full Git checkout is required.

Periodic releases are globally monotonic. If the latest valid release belongs to a later period than the current UTC period, calculation fails rather than moving backwards. Reruns are idempotent only when `HEAD` already owns the latest valid release tag for the current period; an older release tag on `HEAD` is not reused after a later release exists elsewhere.

`scheme` is part of the public contract so other release-identifier strategies can be added later without changing the action path. `periodic` is currently the only supported value.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `scheme` | No | `periodic` | Release identifier scheme. Currently only `periodic` is supported. |
| `period` | No | `month` | Sequence reset boundary: `year`, `month`, `week`, or `day`. |
| `period-format` | No | period-specific | Optional `strftime`-style format for the period label. Supported tokens are `%Y`, `%m`, `%d`, `%G`, and `%V` as appropriate for the selected period. |
| `digits` | No | `4` | Number of zero-padded digits in the sequence. Supported values are `1` through `9`. |
| `tag-prefix` | No | `r` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `release` | Release identifier without the configured tag prefix, for example `202609-0004`. |
| `tag` | Release tag including the configured prefix, for example `r202609-0004`. |
| `previous-tag` | Previous valid release tag, or empty for the first release. On an idempotent rerun this is the release preceding the reused tag. |
| `scheme` | Scheme used to calculate the release. |
| `period` | Rendered period label used in the release identifier. |
| `sequence` | Zero-padded sequence within the period. |

The periodic scheme uses the runner's UTC date. The implementation accepts an internal `PERIOD_VALUE` environment override for deterministic tests; this is not an action input.
