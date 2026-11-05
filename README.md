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
| `python-ml` | `repo-hygiene`, `secrets`, `python`, `apple-silicon`, `make-test` |

The steps have no dependencies on each other, so they run in parallel on
separate agents.

## Checks

| Check          | Fails when                                                                                  |
|----------------|---------------------------------------------------------------------------------------------|
| `repo-hygiene` | The commit tracks a model or dataset file (`.safetensors`, `.gguf`, `.pt`, `.parquet`, and similar) or any file over 5 MiB. |
| `secrets`      | Any commit in history contains a credential, such as a Hugging Face or cloud token. A secret deleted later still fails, because it stays readable in history and must be rotated. Uses gitleaks 8.30.1, downloaded from GitHub and checked against a pinned SHA-256. |
| `python`       | In a repository with Python files: requires a uv project (tracked `pyproject.toml` and `uv.lock`, no `requirements*.txt`, `Pipfile`, `poetry.lock`, `pdm.lock`, `setup.py`, or `environment.yml`), then runs `uv sync --locked` (fails when `uv.lock` is out of date), then `ruff check`, `ruff format --check`, and `pytest` at the versions in the repository's `uv.lock`. The project must list `ruff` and `pytest` in its `dev` dependency group. Uses uv 0.13.1, checked against a pinned SHA-256. Passes without running anything when there are no Python files. |
| `apple-silicon` | In a repository with Python files, the project is not ready for Apple Silicon (MLX, or PyTorch on MPS): `uv.lock` does not require macOS arm64 through `[tool.uv] required-environments`; the macOS arm64 lock contains a CUDA-only package (bitsandbytes, flash-attn, xformers, triton, deepspeed, vllm, unsloth, `nvidia-*`, ...); or code and configuration use an NVIDIA-only setting listed in `lib/apple-silicon-rules.tsv` (`cuda` devices, `torch.cuda`, `nccl`, `flash_attention_2`, bitsandbytes quantization and optimizers, fp16 mixed precision, multi-GPU accelerate modes). Each rule prints the Apple alternative; end a line with `# apple-silicon: allow` to accept it. On an Apple Silicon Mac it also fails when the project's Python runs under Rosetta or PyTorch/MLX cannot reach the GPU. |
| `make-test`    | The repository has no `Makefile`, the `Makefile` has no `test` target, or `make test` fails. `make test` is the one command people and agents run to verify a change. In a uv project, the pinned uv is on `PATH` while it runs. |

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
