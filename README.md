# buildkite-pipelines

Shared Buildkite pipelines and checks, loaded as a
[Buildkite plugin](https://buildkite.com/docs/pipelines/integrations/plugins).
Repositories reference one version tag of this repo; the shared pipeline and
every check it runs come from that tag.

## Use it in a repository

Create `.buildkite/pipeline.yml` in the repository:

```yaml
steps:
  - label: ":pipeline: Upload shared CI"
    plugins:
      - https://github.com/bajor/buildkite-pipelines#v1.0.0:
          pipeline: python-ml
```

Write the reference without a `.git` suffix. The Buildkite agent derives the
plugin's option variables from the last URL segment, and `.git` would rename
them from `BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_*` to
`BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_GIT_*`.

To upgrade, change the tag. To pin exactly, use a commit SHA instead of a tag.

## How it works

```text
.buildkite/pipeline.yml step (plugin #vX, pipeline: python-ml)
  --> hooks/command
  --> lib/upload-pipeline.sh
  --> buildkite-agent pipeline upload
        |
        v
uploaded steps (plugin #vX, check: <name>), one job each
  --> hooks/command
  --> checks/<name>.sh
```

The plugin has two modes, chosen by its single option:

| Option     | Effect                                                              |
|------------|---------------------------------------------------------------------|
| `pipeline` | Uploads `pipelines/<name>.yml` as this build's steps.               |
| `check`    | Runs `checks/<name>.sh` in the current checkout.                    |

`lib/upload-pipeline.sh` replaces `__PLUGIN__` in the template with the exact
plugin reference the uploading step used, read from `BUILDKITE_PLUGINS`.

Checkout of Entire repositories is handled by Buildkite's own `entire` plugin,
which Buildkite adds to each job of an Entire-connected pipeline. This plugin
lives on GitHub because agents fetch plugins with plain `git clone`, and Entire
requires authentication even for public repositories.

## Pipelines

| Pipeline    | Steps                                   |
|-------------|-----------------------------------------|
| `python-ml` | `repo-hygiene`                          |

## Checks

| Check          | Fails when                                                                                  |
|----------------|---------------------------------------------------------------------------------------------|
| `repo-hygiene` | The commit tracks a model or dataset file (`.safetensors`, `.gguf`, `.pt`, `.parquet`, and similar) or any file over 5 MiB. |

## Add a check

1. Add an executable `checks/<name>.sh`. A nonzero exit fails the step.
2. Add a step with `check: <name>` to each template in `pipelines/` that should run it.
3. Add a test in `tests/<name>.bats`, run `make test`, and release a new tag.

## Develop

Requirements: `bash`, `git`, [bats-core](https://github.com/bats-core/bats-core),
and [ShellCheck](https://www.shellcheck.net/).

```bash
make test
```

GitHub Actions runs the same target on every pull request.
