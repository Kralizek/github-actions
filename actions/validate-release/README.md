# Validate GitHub release

Validates GitHub release metadata against the checked-out Git repository.

The action requires a full checkout containing tags. It verifies that the tag is a valid `v`-prefixed Semantic Version, that the tag resolves to the checked-out commit, and that GitHub's prerelease flag matches the tag's prerelease component.

Strict Semantic Versioning rules are enforced, including no leading zeroes in major/minor/patch values or numeric prerelease identifiers. Build metadata is supported.

## Inputs

| Input | Required | Description |
|---|---:|---|
| `tag` | Yes | Release tag, normally `github.event.release.tag_name`. |
| `prerelease` | Yes | GitHub prerelease flag, normally `github.event.release.prerelease`. |

## Outputs

| Output | Description |
|---|---|
| `version` | Semantic Version without the leading `v`. |

## Example

```yaml
- uses: Kralizek/github-actions/actions/validate-release@v1
  with:
    tag: ${{ github.event.release.tag_name }}
    prerelease: ${{ github.event.release.prerelease }}
```
