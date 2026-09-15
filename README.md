# github-actions

Reusable GitHub Actions and workflows.

## Actions

| Action | Description |
|---|---|
| [Calculate next release](actions/calculate-next-release/README.md) | Calculates the next stable SemVer release from Git tags using a patch, minor, or major bump. |

## Releasing

Releases follow Semantic Versioning and use `v<major>.<minor>.<patch>` tags.

Use the **Create release** workflow to select a patch, minor, or major bump. The workflow calculates the next version from the latest stable release tag, creates the GitHub release, and processes it by moving the corresponding `v<major>` and `v<major>.<minor>` tags to the released commit.

Use the workflow's `dry_run` option to calculate the next release without creating it.

The automated release calculation requires at least one existing stable SemVer tag as its baseline.
