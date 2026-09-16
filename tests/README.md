# Tests

Behavioral tests live under `tests/<suite>/test.sh`, and `tests/run.sh` discovers and executes every suite.

Tests should:

- be runnable locally with Bash;
- create and clean up their own temporary fixtures;
- exercise the public behavior of the action or workflow primitive they cover;
- avoid depending on repository state outside their fixture.

The validation workflow syntax-checks shell scripts before running the suites. It also installs Deno and type-checks the Deno-backed `calculate-next-release` action before its behavioral suite executes.
