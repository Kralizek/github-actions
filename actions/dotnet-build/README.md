# .NET build and test

Opinionated composite action for the common .NET repository build sequence: checkout, SDK setup, restore, formatting verification, build, and test.

Use this action when a repository needs custom steps around the common build path, such as coverage processing, package validation, or smoke tests. For the complete library happy path, prefer the reusable `dotnet-ci.yml` workflow.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `global_json_file` | No | `global.json` | Path to `global.json`. Leave empty to use `dotnet_version`. |
| `dotnet_version` | No | | SDK version used when `global_json_file` is empty. |
| `configuration` | No | `Release` | Build configuration. |
| `working_directory` | No | `.` | Working directory for .NET commands. |
| `checkout` | No | `true` | Whether to checkout the caller repository. |
| `fetch_depth` | No | `0` | Checkout fetch depth. Full history supports MinVer and similar tools. |
| `format` | No | `true` | Run `dotnet format --verify-no-changes`. |
| `test` | No | `true` | Run `dotnet test`. |
| `test_arguments` | No | `--logger GitHubActions` | Additional arguments passed to `dotnet test`. |

## Example

```yaml
- uses: Kralizek/github-actions/actions/dotnet-build@v1
  with:
    global_json_file: global.json
```
