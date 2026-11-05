#!/usr/bin/env bash
# Keeps a fine-tuning project runnable on Apple Silicon (MLX, or PyTorch on
# MPS) instead of NVIDIA CUDA:
#   1. uv.lock requires macOS arm64 ([tool.uv] required-environments), so
#      `uv lock` refuses any version without an Apple Silicon wheel.
#   2. The locked packages for macOS arm64 include no CUDA-only library.
#   3. Code and configuration use no NVIDIA-only setting
#      (lib/apple-silicon-rules.tsv lists them with the Apple alternative).
#   4. On an Apple Silicon Mac only: the project's Python is native arm64, not
#      Rosetta, and PyTorch and MLX, when installed, reach the GPU.
# Repositories without Python files pass. Every part runs; any failure fails
# the check.
set -euo pipefail

if [[ -z "$(git ls-files -- '*.py' pyproject.toml)" ]]; then
  echo "No Python files; no Apple Silicon checks to run."
  exit 0
fi

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/uv.sh
source "$plugin_dir/lib/uv.sh"

readonly apple_silicon_marker="platform_machine == 'arm64' and sys_platform == 'darwin'"
# Oldest macOS with arm64 wheels for torch and mlx.
readonly macos_deployment_target="14.0"
readonly cuda_only_packages='^(bitsandbytes|flash-attn|xformers|triton|deepspeed|vllm|unsloth|unsloth-zoo|auto-gptq|apex|cupy.*|nvidia-.*)$'
readonly allow_marker="apple-silicon: allow"

failures=0
fail() {
  echo "apple-silicon: $*" >&2
  failures=$((failures + 1))
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/apple-silicon.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
uv="$(install_uv apple-silicon "$work_dir")"

echo "--- :apple: uv.lock requires macOS arm64"
# Only the required-markers block counts: dependency markers in uv.lock can
# contain the same text without requiring the platform.
required_markers="$(sed -n '/^required-markers = \[/,/^\]/p' uv.lock 2>/dev/null || true)"
if ! grep -qF "\"$apple_silicon_marker\"" <<<"$required_markers"; then
  fail "add to pyproject.toml: [tool.uv] required-environments = [\"sys_platform == 'darwin' and platform_machine == 'arm64'\"], then run uv lock"
fi
"$uv" lock --check || fail "uv.lock does not match pyproject.toml; run uv lock"

echo "--- :apple: no CUDA-only packages for macOS arm64"
# A dry run into an empty environment lists every locked package for the target.
resolution="$(UV_PROJECT_ENVIRONMENT="$work_dir/venv" MACOSX_DEPLOYMENT_TARGET="$macos_deployment_target" \
  "$uv" sync --frozen --dry-run --python-platform aarch64-apple-darwin 2>&1)" \
  || fail "locked packages do not install on macOS $macos_deployment_target arm64: $resolution"
packages="$(sed -n 's/^ + \([^=]*\)==.*/\1/p' <<<"$resolution")"
cuda_packages="$(grep -E "$cuda_only_packages" <<<"$packages" || true)"
if [[ -n "$cuda_packages" ]]; then
  fail "CUDA-only packages in the macOS arm64 lock: ${cuda_packages//$'\n'/ }. Use mlx / mlx-lm or PyTorch on MPS."
fi

echo "--- :apple: no NVIDIA-only settings in code and configuration"
while IFS=$'\t' read -r pattern advice <&3; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  status=0
  matches="$(git grep -n -I -E -e "$pattern" -- '*.py' '*.ipynb' '*.yaml' '*.yml' '*.json' '*.toml' '*.cfg' '*.sh' \
    ':(exclude)uv.lock' ':(exclude).entire/' ':(exclude).claude/')" || status=$?
  if ((status > 1)); then
    exit "$status"
  fi
  matches="$(grep -vF "$allow_marker" <<<"$matches" || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "$advice"
  fi
done 3<"$plugin_dir/lib/apple-silicon-rules.tsv"

if [[ "$(uname -s)" == "Darwin" && "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
  echo "--- :apple: native arm64 Python and GPU access on this Mac"
  "$uv" run --locked python - <<'EOF' || fail "the project's Python cannot use Apple Silicon natively (see above)"
import importlib.util
import platform
import sys

problems = []
if platform.machine() != "arm64":
    problems.append(f"Python runs as {platform.machine()}, likely under Rosetta; use an arm64 Python")
if importlib.util.find_spec("torch"):
    import torch

    if not torch.backends.mps.is_available():
        problems.append("PyTorch cannot use the GPU: torch.backends.mps.is_available() is False")
if importlib.util.find_spec("mlx"):
    import mlx.core as mx

    if mx.default_device() != mx.gpu:
        problems.append(f"MLX default device is {mx.default_device()}, not the GPU")
for problem in problems:
    print(problem, file=sys.stderr)
sys.exit(1 if problems else 0)
EOF
fi

if ((failures > 0)); then
  exit 1
fi
echo "Ready for Apple Silicon."
