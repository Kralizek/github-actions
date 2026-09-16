# Calculate next release

Calculates the next repository release identifier independently of package/version semantics.

The default `calendar` scheme uses tags in the form `rYYYYMM-NNNN`: the current UTC year/month is the release period and the four-digit sequence starts at `0001` for each new month. For example, after `r202609-0004`, another release in September 2026 produces `r202609-0005`; the first release in October produces `r202610-0001`.

The action reads Git tags directly rather than GitHub Release objects. Malformed tags are ignored. A full Git checkout is required.

Calendar releases are globally monotonic. If the latest valid calendar release belongs to a later period than the current UTC month, calculation fails rather than moving the release sequence backwards. Reruns are idempotent only when `HEAD` already owns the latest valid release tag for the current period; an older release tag on `HEAD` is not reused after a later release exists elsewhere.

`scheme` is part of the public contract so other release-identifier schemes can be added later without changing the action path. `calendar` is currently the only supported value.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `scheme` | No | `calendar` | Release identifier scheme. Currently only `calendar` is supported. |
| `tag-prefix` | No | `r` | Prefix used by release tags. |

## Outputs

| Output | Description |
|---|---|
| `release` | Release identifier without the configured tag prefix, for example `202609-0004`. |
| `tag` | Release tag including the configured prefix, for example `r202609-0004`. |
| `previous-tag` | Previous valid release tag, or empty for the first release. On an idempotent rerun this is the release preceding the reused tag. |
| `scheme` | Scheme used to calculate the release. |
| `period` | Calendar period for the release in `YYYYMM` form. |
| `sequence` | Four-digit sequence within the period. |

The calendar scheme uses the runner's UTC date. The implementation accepts an internal `CALENDAR_PERIOD=YYYYMM` environment override for deterministic tests; this is not an action input.
