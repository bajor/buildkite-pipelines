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
| `python-ml` | `repo-hygiene`, `secrets`, `python`, `apple-silicon`, `make-test`, `changelog` |
| `python-ml-nvidia` | `repo-hygiene`, `secrets`, `python`, `linux-nvidia`, `make-test`, `changelog` |
| `verification` | `repo-hygiene`, `secrets`, worker-owned `verification` |

Use `pipeline: python-ml-nvidia` for Linux x86-64 repositories that use an
NVIDIA GPU. The original `python-ml` pipeline remains for Apple Silicon.
Buildkite hosted Linux agents have no GPU, so the NVIDIA pipeline checks the
dependency lock, lint, tests, and repository policy, not CUDA execution.

The steps have no dependencies on each other, so they run in parallel.
Python ML steps use the default queue. The verification job requires a separately
provisioned `trusted-verification` queue.

### Verification orchestration (infrastructure prerequisite)

Select `pipeline: verification` at an approved immutable plugin commit. The
existing Python ML pipelines remain unchanged. This template reuses hygiene and
secret checks, then requests verification from a future worker-owned backend.
It implements no product checks, source materialization, receipts or merge gate.

The request adapter requires `/opt/buildkite-verification/bin/verifier` and
`/etc/buildkite-verification/policy.sha256` (one lowercase SHA-256 digest).
Missing paths, invalid pins, absent build/job identity, non-full commit IDs and
backend failures return nonzero. `HEAD`, short SHAs and implicit merge refs must
be resolved by the trusted scheduler before dispatch. Local `run-local
verification` requires this provisioned backend and job context; ordinary local
product checks remain consumer-specific commands.

Proposed protocol 2, not an available integration:

`verifier request-and-wait --protocol-version 2 --candidate-revision SHA
--policy-sha256 DIGEST --build-id ID --job-id ID`

All arguments are untrusted request hints. The adapter clears inherited job
credentials, Git configuration and PATH before invoking the fixed entrypoint.
It does not inspect Git, execute candidate tests, validate receipts or upload
artifacts. The backend must independently authenticate repository, pipeline,
build/job/attempt and exact candidate/base revisions through a protected control
plane. It must reject mismatches, missing gates, stale results and unsupported
protocols, and obtain a fresh private source snapshot rather than trust the
candidate checkout, its Git configuration, ignored files or hooks.

The backend runs tests without verifier credentials, retains failure artifacts,
and publishes authenticated evidence from a separate authority. It returns zero
only after the required checks and evidence complete. The required merge gate
must independently verify that evidence and the approved job origin. A green
plugin step, its label, queue name or candidate-uploaded artifact is never merge
authorization. The test doubles establish request/failure propagation only.

Before production use, a separate infrastructure change must demonstrate protected
worker binaries/policies and parent directories, isolated disposable jobs,
credential separation, authenticated exact-source evidence and host admission.
Candidate-selected plugins, repository hooks and environment changes cannot be
trusted to enforce these controls. Use agent-level pre-bootstrap policy and
approved plugin/command pins; evaluate self-hosted signed pipelines where
supported. These protections are not implemented by this template. See
[Buildkite security](https://buildkite.com/docs/agent/self-hosted/security) and
[signed pipeline limits](https://buildkite.com/docs/agent/self-hosted/security/signed-pipelines).

A missing queue can leave a job waiting before its runtime timeout begins. The
future scheduler must enforce a queue/start deadline and fail admission on
missing/expired jobs. No Buildkite worker execution is established by local tests.
Consumer repositories keep application-specific scenarios and feature maps local;
shared pipeline/check implementations remain here and are referenced by pin.

## Buildkite settings

The Python ML pipelines target Buildkite hosted Linux agents. GitHub Actions in
this repository tests the plugin itself; consumer CI runs on Buildkite.

Each Python ML template sets, for every step:

| Setting | Value | Why |
|---------|-------|-----|
| `cache` volume `python-ml` at `/tmp/buildkite-cache` | `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR` inside it, `UV_LINK_MODE=copy` | uv packages and Pythons persist between builds instead of downloading each time. Only jobs that exit 0 save changes; the cache is best-effort. |
| `timeout_in_minutes` | 15 | A hung job cannot run up agent minutes. |
| `retry.automatic` | `exit_status: -1`, `limit: 2` | A job whose agent is lost is retried; check failures are not. |

Set these on each consumer pipeline (Pipeline Settings, or the REST API fields
in parentheses):

| Setting | Value | Why |
|---------|-------|-----|
| Skip intermediate builds (`skip_queued_branch_builds`) | on, filter `!main` | Only the newest queued build of a trail branch runs. |
| Cancel intermediate builds (`cancel_running_branch_builds`) | on, filter `!main` | A new push to a trail branch stops the running build. `main` builds always finish. |
| Default and maximum command step timeout (`default_command_step_timeout`, `maximum_command_step_timeout`) | 15, 30 | Caps steps that set no timeout, such as the upload step. |

## What a repository needs to pass the Python ML pipelines

1. No model weights, datasets, or files over 5 MiB in git.
2. No credentials anywhere in git history.
3. Python managed by uv: tracked `pyproject.toml` and `uv.lock`, with `ruff`
   and `pytest` in the `dev` dependency group, and no other dependency files.
4. In `pyproject.toml`, require the deployment platform. For `python-ml`:

   ```toml
   [tool.uv]
   required-environments = ["sys_platform == 'darwin' and platform_machine == 'arm64'"]
   ```

   For `python-ml-nvidia`, require
   `"sys_platform == 'linux' and platform_machine == 'x86_64'"` instead.
5. For `python-ml`, no CUDA-only packages or NVIDIA-only settings (see
   `apple-silicon`). For `python-ml-nvidia`, Linux dependency resolution must
   exclude Apple-only packages. Run a CUDA smoke test on the real GPU host.
6. A `Makefile` whose `test` target runs every test and linter.
7. A `CHANGELOG.md` whose newest section is `## [X.Y.Z] - YYYY-MM-DD`, with a
   higher version on every branch than on `main`.

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

### `linux-nvidia`

For a Python project, verifies `uv.lock` requires Linux x86-64, matches
`pyproject.toml`, resolves for Linux x86-64, and does not install MLX or other
Apple-only packages on Linux. CUDA libraries and FP16 settings are allowed.
This check does not require an NVIDIA device on a hosted agent. Before a push,
test CUDA availability and one FP16 operation on the actual host; a matching
lock alone cannot establish GPU compatibility.

### `make-test`

Fails when the repository has no `Makefile`, the `Makefile` has no `test`
target, or `make test` fails. `make test` is the one command people and agents
run to verify a change. In a uv project the pinned uv is on `PATH` while it
runs.


### `changelog`

Fails when `CHANGELOG.md` is missing or its newest section is not
`## [X.Y.Z]` (optionally ` - YYYY-MM-DD`). On any branch other than the base
branch it also fails unless that version is higher than the newest version on
the base branch, so every change adds a release. The base branch is
`CHANGELOG_BASE_BRANCH`, else the pull request base, else the pipeline's
default branch, else `main`.
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
On a branch that does not contain the command, such as one created before the
CI setup, the hook prints a message and the push continues.
A push that only deletes branches or tags skips the checks too. Running
`install-pre-push-hook` again updates an installed hook to the current version.

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

The tests for `secrets`, `python`, `apple-silicon`, `linux-nvidia`, and `run-local` download
gitleaks, uv, Python, and packages, so they need network access. GitHub Actions
runs `make test` and the shared secret scanning workflow on every pull request.

## Release

Every pull request to `main` ends with a commit that adds a version section at
the top of `CHANGELOG.md`. GitHub Actions in this repository:

| Workflow | When | What |
|----------|------|------|
| `ci.yml` | pull requests, pushes to `main` | `make test`, and `checks/changelog.sh` for a valid, higher version |
| `changelog.yml` | pull requests to `main` | `changelog-check.yml` from bajor/github-workflows: `CHANGELOG.md` was modified |
| `release.yml` | pushes to `main` | `release.yml` from bajor/github-workflows: tags `vX.Y.Z` and publishes a GitHub release from the newest section |
| `secret-scanning.yml` | pull requests, pushes to `main` | shared secret and sensitive-data scanning |

`release.yml` only diffs the last commit pushed, so the changelog commit must
be the last commit of each pull request. To adopt a release in a consumer,
change the tag in its `.buildkite/pipeline.yml`, run `scripts/ci-local.sh`, and
push.
