# Kralizek GitHub Actions

Opinionated GitHub Actions and reusable workflows shared across my repositories.

The goal of this repository is to centralize automation that is genuinely common across projects while keeping repository-specific orchestration close to the code it belongs to.

## Design principles

- **Opinionated defaults over endless configuration.** Shared automation should encode the conventions used across the repositories.
- **Composable actions, thin workflows.** Composite actions provide reusable building blocks; reusable workflows provide the common happy path.
- **Repository-specific checks stay local.** Package smoke tests, benchmarks, deployment topology, database migrations, and product-specific release rules should remain in their repositories unless multiple projects converge on the same behavior.
- **Callers own policy.** Publishing and deployment workflows should not hide repository, environment, or permission decisions.
- **Version consumers.** Repositories should consume released tags such as `@v1` rather than `@master` once this repository starts publishing releases.

## Actions

| Action | Description |
|---|---|
| [Calculate next release](actions/calculate-next-release/README.md) | Calculates the next stable or channel-based prerelease SemVer release from Git tags, with an optional minimum-version floor. |
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
  calculate-next-release/ # Calculate stable or channel-based prerelease versions
  dotnet-build/            # Shared .NET restore/format/build/test primitive
  validate-release/        # Validate SemVer tag and GitHub release metadata
tests/
  run.sh                    # Discover and run Bash test suites
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

## Calculate next release

Stable release:

```yaml
- uses: Kralizek/github-actions/actions/calculate-next-release@master
  id: release
  with:
    bump: minor
```

Prerelease channel with a version floor:

```yaml
- uses: Kralizek/github-actions/actions/calculate-next-release@master
  id: release
  with:
    bump: minor
    channel: rc
    minimum-version: 2.0.0
```

With `v1.2.3` as the latest stable tag, the latter produces `v2.0.0-rc.1`, then `v2.0.0-rc.2`, and so on. Without `minimum-version`, the same request would target `v1.3.0-rc.1`. Each channel has an independent sequence against the same stable target.

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

Use the **Create release** workflow from `master` to select a patch, minor, or major bump. The workflow calculates the next version from the latest stable release tag, creates the GitHub release, and processes it by moving the corresponding `v<major>` and `v<major>.<minor>` tags to the released commit.

Use the workflow's `dry_run` option to calculate the next release without creating it. The automated release calculation requires at least one existing stable SemVer tag as its baseline.

## License

MIT. See [`LICENSE`](LICENSE).
