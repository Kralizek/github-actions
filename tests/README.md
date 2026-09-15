# Tests

Bash-backed behavior is tested with small, self-contained suites under `tests/<suite>/test.sh`.

Run all suites locally with:

```bash
bash tests/run.sh
```

The runner discovers every `tests/*/test.sh` file. Each suite should:

- use `set -euo pipefail`;
- create and clean up its own temporary fixtures;
- invoke the production script or action behavior directly;
- fail with a non-zero exit code when an assertion fails;
- avoid depending on execution order or state from another suite.

When wrapping a command in a helper function, propagate its exit status explicitly. Bash disables some `set -e` behavior for functions evaluated as conditions, so negative tests should not rely on `errexit` alone.

The release-calculation suite covers bootstrap behavior (default `0.1.0` and explicit `minimum-version`) as well as bumps after a stable baseline exists.

The validation workflow also runs `bash -n` over shell scripts under both `actions/` and `tests/` before executing the suites.
