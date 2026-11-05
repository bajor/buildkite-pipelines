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

| Pipeline    | Steps                                                              |
|-------------|--------------------------------------------------------------------|
| `python-ml` | `repo-hygiene`, `secrets`, `python`, `apple-silicon`, `make-test` |

The steps have no dependencies on each other, so they run in parallel on
separate agents of the default queue.

## What a repository needs to pass `python-ml`

1. No model weights, datasets, or files over 5 MiB in git.
2. No credentials anywhere in git history.
3. Python managed by uv: tracked `pyproject.toml` and `uv.lock`, with `ruff`
   and `pytest` in the `dev` dependency group, and no other dependency files.
4. In `pyproject.toml`:

   ```toml
   [tool.uv]
   required-environments = ["sys_platform == 'darwin' and platform_machine == 'arm64'"]
   ```

5. No CUDA-only packages or NVIDIA-only settings (see `apple-silicon`).
6. A `Makefile` whose `test` target runs every test and linter.

## Checks

### `repo-hygiene`

Fails when the commit tracks a model or dataset file (`.safetensors`, `.gguf`,
`.bin`, `.pt`, `.ckpt`, `.onnx`, `.parquet`, `.arrow`, and similar) or any file
over 5 MiB. Fine-tuning repositories keep weights on external storage, and a
committed file stays in git history after it is deleted.

### `secrets`

Fails when any commit in history contains a credential, such as a Hugging Face
or cloud token. A secret deleted later still fails, because it stays readable
in history and must be rotated. Runs gitleaks 8.30.1, downloaded from GitHub and
checked against a pinned SHA-256.

### `python`

In a repository with Python files:

1. Fails unless it is a uv project: tracked `pyproject.toml` and `uv.lock`, and
   none of `requirements*.txt`, `Pipfile`, `poetry.lock`, `pdm.lock`,
   `setup.py`, `environment.yml`.
2. Runs `uv sync --locked`, which fails when `uv.lock` is out of date.
3. Runs `ruff check`, `ruff format --check`, and `pytest` at the versions in the
   repository's `uv.lock`.

Uses uv 0.13.1, checked against a pinned SHA-256. Passes without running
anything when there are no Python files.

### `apple-silicon`

Keeps fine-tuning runnable on Apple Silicon (MLX, or PyTorch on MPS) instead of
NVIDIA CUDA. In a repository with Python files it fails when:

1. `uv.lock` does not require macOS arm64 through `required-environments`, so
   `uv lock` could pick a version without an Apple Silicon wheel.
2. The lock resolved for macOS 14 arm64 contains a CUDA-only package:
   bitsandbytes, flash-attn, xformers, triton, deepspeed, vllm, unsloth, apex,
   auto-gptq, cupy, or `nvidia-*`.
3. Code or configuration (`.py`, `.ipynb`, `.yaml`, `.json`, `.toml`, `.cfg`,
   `.sh`) uses an NVIDIA-only setting from `lib/apple-silicon-rules.tsv`:

   | Found | Use on Apple Silicon |
   |-------|----------------------|
   | `.cuda()`, `"cuda"` devices, `torch.cuda` | `"mps"`, `torch.backends.mps`, or MLX |
   | `CUDA_VISIBLE_DEVICES`, `cudnn` | nothing; MPS and MLX use the GPU |
   | `nccl` | the `gloo` backend |
   | `flash_attention_2` | `attn_implementation="sdpa"` |
   | bitsandbytes, `load_in_4bit`, 8-bit or paged optimizers | MLX quantization (`mlx_lm.convert -q`, QLoRA in `mlx_lm.lora`), `optim="adamw_torch"` |
   | `fp16=True`, `mixed_precision: fp16` | `bf16` |
   | accelerate `MULTI_GPU`, `DEEPSPEED`, `FSDP` | `distributed_type: NO` |
   | `import` of unsloth, deepspeed, vllm, xformers, triton, apex | mlx-lm, or PyTorch on MPS |

   A line ending in `# apple-silicon: allow` is accepted, for example
   `device = "cuda" if torch.cuda.is_available() else "mps"  # apple-silicon: allow`.
4. On an Apple Silicon Mac only (the local pre-push run): the project's Python
   runs under Rosetta, `torch.backends.mps.is_available()` is false, or MLX's
   default device is not the GPU. Hosted Linux agents skip this part.

### `make-test`

Fails when the repository has no `Makefile`, the `Makefile` has no `test`
target, or `make test` fails. `make test` is the one command people and agents
run to verify a change. In a uv project the pinned uv is on `PATH` while it
runs.

## Run the checks before pushing

Buildkite builds cost money, so find failures locally first. From the root of a
consumer repository, with this plugin cloned at the pinned version:

```bash
<plugin>/bin/run-local python-ml              # runs every check of the pipeline
<plugin>/bin/install-pre-push-hook <command>  # runs <command> before each push
```

`run-local` runs all checks even after a failure and exits nonzero if any failed.
`install-pre-push-hook` keeps the repository's existing pre-push hook, such as
Entire's, and runs it afterwards with the original arguments and stdin. A failing
command stops the push; `git push --no-verify` skips the hook once.

Consumer repositories wrap this in `scripts/ci-local.sh`, which reads the plugin
version and pipeline name from `.buildkite/pipeline.yml` so local and remote CI
run the same checks.

## Add a check or rule

1. Add an executable `checks/<name>.sh`. A nonzero exit fails the step. Tools
   it downloads go through `lib/install-release.sh` with a pinned SHA-256; uv
   comes from `lib/uv.sh`.
2. Add a step with `check: <name>` to each template in `pipelines/` that should run it.
3. Add a test in `tests/<name>.bats`, run `make test`, and release a new tag.

A new NVIDIA-only setting for `apple-silicon` is one line in
`lib/apple-silicon-rules.tsv`: a `git grep -E` pattern, a tab, and the Apple
alternative.

## Develop

Requirements: `bash`, `git`, [bats-core](https://github.com/bats-core/bats-core),
and [ShellCheck](https://www.shellcheck.net/).

```bash
make test   # ShellCheck, then every bats test
```

The tests for `secrets`, `python`, `apple-silicon`, and `run-local` download
gitleaks, uv, Python, and packages, so they need network access. GitHub Actions
runs `make test` and the shared secret scanning workflow on every pull request.

## Release

1. Merge to `main` with `make test` passing.
2. Tag the merge commit, for example `git tag v1.1.0 && git push origin v1.1.0`.
3. Change the tag in each consumer's `.buildkite/pipeline.yml`, run
   `scripts/ci-local.sh` there, and push.
