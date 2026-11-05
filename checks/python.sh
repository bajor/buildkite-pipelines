#!/usr/bin/env bash
# Lints and tests a uv project with the ruff and pytest versions in its own
# uv.lock, so CI and local runs agree. `uv sync --locked` fails the step when
# uv.lock no longer matches pyproject.toml instead of resolving new versions;
# the later commands then use the lock as is. Repositories without Python
# files pass; repositories with Python must be uv projects.
set -euo pipefail

python_files="$(git ls-files -- '*.py' pyproject.toml)"
if [[ -z "$python_files" ]]; then
  echo "No Python files; no Python checks to run."
  exit 0
fi

# Python projects use uv: dependencies in pyproject.toml, locked in uv.lock.
other_managers="$(git ls-files -- 'requirements*.txt' Pipfile Pipfile.lock poetry.lock pdm.lock setup.py environment.yml)"
missing=""
for file in pyproject.toml uv.lock; do
  [[ -n "$(git ls-files -- "$file")" ]] || missing="$missing $file"
done
if [[ -n "$missing" ]]; then
  echo "Python code without a uv project; commit:$missing (create them with \`uv init\` and \`uv lock\`)." >&2
fi
if [[ -n "$other_managers" ]]; then
  echo "Declare dependencies in pyproject.toml and lock them with uv; remove: ${other_managers//$'\n'/ }" >&2
fi
if [[ -n "$missing" || -n "$other_managers" ]]; then
  exit 1
fi

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/uv.sh
source "$plugin_dir/lib/uv.sh"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/uv.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
uv="$(install_uv python "$work_dir")"

echo "--- :python: uv sync"
"$uv" sync --locked
echo "--- :python: ruff check"
"$uv" run --frozen ruff check .
echo "--- :python: ruff format --check"
"$uv" run --frozen ruff format --check .
echo "--- :python: pytest"
"$uv" run --frozen pytest
