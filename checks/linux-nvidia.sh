#!/usr/bin/env bash
# Verify that a Python project resolves for Linux x86-64 without Apple-only
# packages. Hosted CI has no GPU; a CUDA execution test must run on the host.
set -euo pipefail

if [[ -z "$(git ls-files -- '*.py' pyproject.toml)" ]]; then
  echo "No Python files; no Linux NVIDIA checks to run."
  exit 0
fi

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/uv.sh
source "$plugin_dir/lib/uv.sh"

readonly apple_packages='^(mlx(-.*)?|tensorflow-macos|tensorflow-metal)$'
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/linux-nvidia.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
uv="$(install_uv linux-nvidia "$work_dir")"

python="$("$uv" python find)"
if ! "$python" -c '
import sys
import tomllib

with open(file=sys.argv[1], mode="rb") as lock:
    markers = tomllib.load(lock).get("required-markers", [])
required = {"platform_machine == '\''x86_64'\''", "sys_platform == '\''linux'\''"}
sys.exit(0 if any(set(marker.split(" and ")) == required for marker in markers) else 1)
' uv.lock; then
  echo "linux-nvidia: require Linux x86-64 in [tool.uv] required-environments, then run uv lock" >&2
  exit 1
fi
"$uv" lock --check

resolution="$(UV_PROJECT_ENVIRONMENT="$work_dir/venv" \
  "$uv" sync --frozen --dry-run --python-platform x86_64-unknown-linux-gnu 2>&1)" || {
  echo "linux-nvidia: lock does not resolve for Linux x86-64: $resolution" >&2
  exit 1
}
tree="$("$uv" tree --preview-features json-output --frozen --format json \
  --python-platform x86_64-unknown-linux-gnu)"
packages="$("$python" -c '
import json
import sys

tree = json.load(sys.stdin)
if tree.get("schema", {}).get("version") != "preview" or not isinstance(tree.get("resolution"), dict):
    raise SystemExit("linux-nvidia: unrecognized uv tree JSON schema")
print("\n".join(node["name"] for node in tree["resolution"].values() if node.get("kind") == "package"))
' <<<"$tree")"
apple_only="$(grep -E "$apple_packages" <<<"$packages" || true)"
if [[ -n "$apple_only" ]]; then
  echo "linux-nvidia: Apple-only packages resolved on Linux: ${apple_only//$'\n'/ }" >&2
  exit 1
fi
echo "Ready for Linux x86-64 dependency installation; run a CUDA smoke test on the GPU host."
