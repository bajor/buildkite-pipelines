#!/usr/bin/env bash
# Runs the repository's own `make test`, the one command people and agents
# run to verify a change. Fails when there is no Makefile, when it has no test
# target, or when the target fails. In a uv project the pinned uv goes on PATH
# first, because test targets call it.
set -euo pipefail

if [[ ! -f Makefile ]]; then
  echo "make-test: no Makefile; add one with a test target that runs every test and linter." >&2
  exit 1
fi
# -n prints the recipe without running it and fails when there is no target.
if ! dry_run="$(make -n test 2>&1)"; then
  echo "$dry_run" >&2
  echo "make-test: the Makefile has no test target." >&2
  exit 1
fi

if [[ -f pyproject.toml ]]; then
  plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=lib/uv.sh
  source "$plugin_dir/lib/uv.sh"
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/make-test.XXXXXX")"
  trap 'rm -rf "$work_dir"' EXIT
  uv="$(install_uv make-test "$work_dir")"
  PATH="$(dirname "$uv"):$PATH"
fi

make test
