# Changelog

Every pull request adds a version section at the top of this file, newest
first, in the form `## [X.Y.Z] - YYYY-MM-DD`. Merging it to `main` tags
`vX.Y.Z` and publishes a GitHub release with that section as the notes.
Consumers pin a tag in `.buildkite/pipeline.yml`.

## [0.4.0] - 2026-11-05

### Added

- `python` check: requires a uv project (tracked `pyproject.toml` and `uv.lock`, no other dependency files), then runs `uv sync --locked`, `ruff check`, `ruff format --check`, and `pytest` at the locked versions.
- `lib/install-release.sh` and `lib/uv.sh`: checksum-verified tool downloads shared by checks.

## [0.3.0] - 2026-11-05

### Added

- `secrets` check: gitleaks 8.30.1 scans the full git history for credentials, downloaded with a pinned SHA-256.

## [0.2.0] - 2026-11-05

### Added

- GitHub Actions: secret and sensitive-data scanning (gitleaks, TruffleHog, PII, cached artifacts, sensitive config files) through `secret-scanning.yml` from bajor/github-workflows.

## [0.1.0] - 2026-11-05

### Added

- Buildkite plugin with two modes: `pipeline: <name>` uploads `pipelines/<name>.yml`, and `check: <name>` runs `checks/<name>.sh`. Generated steps reuse the uploading step's plugin reference, so one tag pins the whole pipeline.
- `python-ml` pipeline with the `repo-hygiene` check: fails on tracked model or dataset files and files over 5 MiB.
- GitHub Actions for this repository: `make test` on pull requests and `main`, the changelog check and the release from bajor/github-workflows.
