# Migration candidates

This inventory is intentionally conservative: move behavior only when multiple repositories are doing the same thing for the same reason.

Exported reusable workflows are documented under `docs/workflows/` using the same base filename as the workflow. Internal repository workflows are intentionally excluded from that documentation surface.

## OSS repositories

### AWSSecretsManagerConfigurationExtensions (SMCP)

**Strong first consumer.**

Current CI is the shared happy path almost verbatim:

1. checkout;
2. setup .NET from `global.json`;
3. restore;
4. `dotnet format --verify-no-changes`;
5. build Release with warnings as errors;
6. test with the GitHub Actions logger;
7. pack;
8. upload `.nupkg` / `.snupkg` artifacts.

Candidate migration:

- replace `ci.yml` with a thin caller of `.github/workflows/dotnet-ci.yml`;
- later replace the repeated release build sequence with shared release/publishing primitives.

The release workflow also repeats GitHub Packages publishing, `nuget/login`, NuGet.org publishing, and attaching packages to the GitHub release. Those mechanics should be extracted after the channel policy is normalized with the other OSS repositories.

### MinimalOpenApi (MOA)

**Strong CI consumer, partial release consumer.**

CI has the same restore/format/build/test shape and only needs to specify its package project explicitly.

Candidate migration:

- use `dotnet-ci.yml` with `pack: true` and `pack_project: src/MinimalOpenAPI/MinimalOpenAPI.csproj`;
- keep the package-consumption smoke test local;
- replace the local release-tag validation script with `actions/validate-release`.

The publish workflow contains project-specific package validation and smoke tests, so the overall workflow should stay local for now.

### ObjectConfigurationExtensions (OCP)

**Good source for release conventions, but CI has one project-specific check.**

The basic CI sequence is common, followed by a package-version consistency check across produced packages.

Candidate migration:

- use `actions/dotnet-build` for the shared restore/format/build/test portion;
- keep packing/version-consistency validation local until that check appears in another multi-package repository;
- replace GitHub release metadata validation with `actions/validate-release`;
- use `actions/calculate-next-version` for stable release targets and channel sequencing, passing OCP's configured minimum version as `minimum-version`.

OCP currently contains one of the clearest implementations of the newer manual prerelease flow (`alpha`, `beta`, `rc`, dry-run, generated prerelease versions). The shared `calculate-next-version` action now models the same channel sequencing and version-floor behavior.

### AWSLambdaSharpTemplate (KLT)

**Source of mature release behavior; not a candidate for wholesale workflow replacement.**

KLT's main workflow combines standard .NET build/test/package behavior with template-specific validation and a richer prerelease pipeline. Its benchmark workflows are inherently KLT-specific.

Candidate extraction/adoption:

- release metadata validation;
- `calculate-next-version` for stable and channel-based release selection, passing KLT's configured minimum version as `minimum-version`;
- common NuGet/GitHub Packages publishing mechanics;
- possibly package artifact upload conventions.

Keep local:

- benchmark history and validation;
- template-specific validation;
- release benchmark orchestration;
- anything depending on KLT's package/template topology.

## Product repository used as a secondary reference

### Xilo

Xilo already has a local reusable `build_and_test.yml`, which validates the idea of centralizing the build primitive. Its workflow adds coverage merging/report generation and uses Xilo-specific test settings.

Potential use:

- call `actions/dotnet-build` with `test: false`, then run Xilo's coverage-aware test/reporting steps locally;
- do not move Lambda/web deployment workflows into this repository yet. They encode Xilo deployment topology rather than a general convention.

## Extraction backlog

Suggested order:

1. Adopt `dotnet-ci.yml` in SMCP as the proving consumer.
2. Adopt `dotnet-ci.yml` in MOA CI.
3. Adopt `validate-release` in MOA, OCP, and KLT.
4. Adopt `calculate-next-version` for stable and prerelease creation, using `minimum-version` where projects define a floor. Repositories without a stable baseline bootstrap at `0.1.0` by default.
5. Extract package publishing only when the GitHub Packages / NuGet.org channel policy is identical across at least two repositories.
6. Revisit Xilo for a coverage-oriented .NET workflow or AWS deployment actions after the OSS path has stabilized.

## Things deliberately not centralized yet

- project-specific smoke tests;
- benchmark workflows;
- package-content validation;
- package-version consistency checks that only one repository needs;
- application deployment orchestration;
- infrastructure provisioning;
- release policy that differs by project.

A shared repository should reduce duplication without turning every repository's workflow into a matrix of escape-hatch inputs.
