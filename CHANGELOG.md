# Changelog

Every pull request adds a version section at the top of this file, newest
first, in the form `## [X.Y.Z] - YYYY-MM-DD`. Merging it to `main` tags
`vX.Y.Z` and publishes a GitHub release with that section as the notes.
Consumers pin a tag in `.buildkite/pipeline.yml`.

## [0.2.0] - 2026-11-05

### Added

- GitHub Actions: secret and sensitive-data scanning (gitleaks, TruffleHog, PII, cached artifacts, sensitive config files) through `secret-scanning.yml` from bajor/github-workflows.

## [0.1.0] - 2026-11-05

### Added

- Buildkite plugin with two modes: `pipeline: <name>` uploads `pipelines/<name>.yml`, and `check: <name>` runs `checks/<name>.sh`. Generated steps reuse the uploading step's plugin reference, so one tag pins the whole pipeline.
- `python-ml` pipeline with the `repo-hygiene` check: fails on tracked model or dataset files and files over 5 MiB.
- GitHub Actions for this repository: `make test` on pull requests and `main`, the changelog check and the release from bajor/github-workflows.
