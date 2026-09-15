# Reusable .NET CI

Documentation for [`.github/workflows/dotnet-ci.yml`](../../.github/workflows/dotnet-ci.yml).

Provides the opinionated CI happy path used by .NET library repositories: checkout, SDK setup, restore, formatting verification, build, test, optional NuGet packing, and package artifact upload.

## Usage

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

jobs:
  ci:
    uses: Kralizek/github-actions/.github/workflows/dotnet-ci.yml@v1
    with:
      global_json_file: global.json
      pack: true
```

Callers should pin a released major version such as `@v1`. Use `@master` only while bootstrapping or intentionally testing unreleased changes.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `global_json_file` | string | `global.json` | Workspace-relative path to `global.json`. Set to an empty string to use `dotnet_version` instead. |
| `dotnet_version` | string | empty | .NET SDK version used when `global_json_file` is empty. |
| `configuration` | string | `Release` | Build configuration. |
| `working_directory` | string | `.` | Workspace-relative working directory used by `dotnet` commands. |
| `format` | boolean | `true` | Run `dotnet format --verify-no-changes --no-restore`. |
| `test` | boolean | `true` | Run `dotnet test`. |
| `test_arguments` | string | `--logger GitHubActions` | Additional arguments passed to `dotnet test`. |
| `pack` | boolean | `false` | Pack NuGet packages and upload them as a workflow artifact. |
| `pack_project` | string | empty | Optional project or solution passed to `dotnet pack`, relative to `working_directory`. Empty uses the default project/solution there. |
| `pack_output` | string | `./artifacts/packages` | Workspace-relative output directory for packed packages. |
| `artifact_name` | string | `nuget-packages` | Name of the uploaded package artifact. |
| `artifact_path` | string | package globs under `./artifacts/packages` | Workspace-relative files uploaded when packing is enabled. |

All path inputs except `pack_project` are resolved from the caller workspace. Changing `working_directory` therefore does not silently relocate package outputs or artifact globs.

## Permissions

The workflow requests only:

```yaml
permissions:
  contents: read
```

Publishing, release creation, deployment, and other write operations remain the caller repository's responsibility.

## Behavior and conventions

The workflow always checks out full Git history (`fetch-depth: 0`) so tag-based versioning tools such as MinVer can calculate package versions correctly.

Builds run with warnings as errors. Formatting verification and tests can be disabled when the repository needs to run custom equivalents locally, but repositories with substantial custom behavior may be better served by the lower-level [`dotnet-build`](../../actions/dotnet-build/README.md) composite action.

When `pack` is enabled, the workflow runs `dotnet pack --no-build` and uploads both `.nupkg` and `.snupkg` files by default.
