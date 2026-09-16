# Kralizek GitHub Actions

Opinionated GitHub Actions and reusable workflows shared across my repositories.

The goal of this repository is to centralize automation that is genuinely common across projects while keeping repository-specific orchestration close to the code it belongs to.

## Design principles

- **Opinionated defaults over endless configuration.** Shared automation should encode the conventions used across the repositories.
- **Composable actions, thin workflows.** Composite actions provide reusable building blocks; reusable workflows provide the common happy path.
- **Repository-specific checks stay local.** Package smoke tests, benchmarks, deployment topology, database migrations, and product-specific release rules should remain in their repositories unless multiple projects converge on the same behavior.
- **Callers own policy.** Publishing and deployment workflows should not hide repository, environment, or permission decisions.
- **Version consumers.** Repositories should consume released tags such as `@v1` rather than `@master` once this repository starts publishing releases.
- **Reusable workflows declare their audience.** Every workflow exposing `workflow_call` must either be exported and documented under `docs/workflows/`, or explicitly marked `# internal-workflow` when it exists only for this repository.

## Actions

| Action | Description |
|---|---|
| [Calculate next version](actions/calculate-next-version/README.md) | Calculates the next stable or channel-based prerelease SemVer version from Git tags, with an optional minimum-version floor and `0.1.0` bootstrap target. |
| [.NET build and test](actions/dotnet-build/README.md) | Opinionated checkout, SDK setup, restore, format, build, and test primitive for .NET repositories. |
| [Validate GitHub release](actions/validate-release/README.md) | Strictly validates a SemVer release tag, its target commit, and the GitHub prerelease flag. |

## Reusable workflows

| Workflow | Description |
|---|---|
| [Reusable .NET CI](docs/workflows/dotnet-ci.md) | Restore, format, build, test, and optionally pack/upload NuGet packages. |

Only workflows intended to be consumed by other repositories are documented under `docs/workflows/`. Exported workflows are declared in [`docs/workflows/exports.txt`](docs/workflows/exports.txt), and each must have a Markdown file with the same base name as the workflow file. Reusable workflows that exist only for this repository are explicitly marked `# internal-workflow` and are not part of the public documentation surface. Validation enforces the contract in both directions.

## Initial scope

The first candidates are the patterns repeated across the .NET OSS repositories:

- checkout and .NET SDK setup;
- restore, formatting verification, build-as-errors, and test;
- optional NuGet packing and workflow artifacts;
- stable and channel-based prerelease version calculation;
- Semantic Versioning / GitHub release metadata validation.

Release publishing is intentionally being extracted incrementally: KLT, SMCP, OCP, and MinimalOpenAPI currently have similar but not identical NuGet publishing policies.

## Repository layout

```text
actions/
  calculate-next-version/ # Calculate stable or channel-based prerelease SemVer versions
  dotnet-build/           # Shared .NET restore/format/build/test primitive
  validate-release/       # Validate SemVer tag and GitHub release metadata
tests/
  run.sh                   # Discover and run Bash test suites
  <suite>/test.sh           # Behavioral tests for Bash-backed actions/workflows
.github/workflows/
  dotnet-ci.yml             # Reusable opinionated CI workflow for .NET libraries
  create-release.yml        # Release this actions repository
  process-release.yml       # Maintain major/minor floating tags
  validate.yml              # Validate actions, scripts, tests, and workflows
docs/
  workflows/
    exports.txt              # Public reusable workflow manifest
    dotnet-ci.md             # Documentation for exported dotnet-ci.yml
  migration-candidates.md
```

See [`docs/migration-candidates.md`](docs/migration-candidates.md) for the inventory and extraction plan.

## Bash tests

Bash-backed behavior is tested outside the validation workflow. Each suite lives under `tests/<suite>/test.sh`, and `tests/run.sh` discovers and executes every suite.

The validation workflow first runs `bash -n` over shell scripts under both `actions/` and `tests/`, then executes the suites. This keeps behavioral assertions versioned next to the code without turning `.github/workflows/validate.yml` into a test implementation.

When adding Bash-backed behavior, add or extend a matching suite under `tests/`. Tests should create their own temporary fixtures and clean them up so they remain isolated and runnable locally with `bash tests/run.sh`.

See [`tests/README.md`](tests/README.md) for the test conventions.

## Reusable .NET CI workflow

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

jobs:
  ci:
    uses: Kralizek/github-actions/.github/workflows/dotnet-ci.yml@master
    with:
      global_json_file: global.json
      pack: true
```

The `@master` reference is suitable while bootstrapping this repository. Consumers should move to a stable major tag such as `@v1` after the first release.

## Composite .NET build action

Use the lower-level action when a repository needs extra steps around the standard build, for example package smoke tests or coverage processing.

```yaml
steps:
  - uses: Kralizek/github-actions/actions/dotnet-build@master
    with:
      global_json_file: global.json
```

## Release validation action

```yaml
- uses: Kralizek/github-actions/actions/validate-release@master
  with:
    tag: ${{ github.event.release.tag_name }}
    prerelease: ${{ github.event.release.prerelease }}
```

The action enforces strict Semantic Versioning, verifies that the tag points at the checked-out commit, and checks that GitHub's prerelease flag matches the tag.

## Releasing this repository

Releases follow Semantic Versioning and use `v<major>.<minor>.<patch>` tags.

Use the **Create release** workflow from `master` to select a patch, minor, or major bump. `minor` is preselected. When no stable release exists yet, the first release is `v0.1.0`; the selected bump only starts applying after that first stable release exists. Stable releases also move the corresponding `v<major>` and `v<major>.<minor>` tags to the released commit.

Use the workflow's `dry_run` option to calculate the release without creating it.

## License

MIT. See [`LICENSE`](LICENSE).
