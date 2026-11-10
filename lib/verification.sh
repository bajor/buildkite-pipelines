#!/usr/bin/env bash
set -euo pipefail

verifier="${1:?worker verifier required}"
policy_file="${2:?worker policy file required}"

fail() {
  echo "verification: $*" >&2
  exit 1
}

[[ -x "$verifier" ]] || fail "worker-owned verifier is unavailable"
[[ -f "$policy_file" ]] || fail "worker-owned policy pin is unavailable"
policy_sha256="$(<"$policy_file")"
[[ "$policy_sha256" =~ ^[a-f0-9]{64}$ ]] || fail "invalid policy SHA-256"
source_revision="$(git rev-parse --verify HEAD)"
[[ "${BUILDKITE_COMMIT:-}" == "$source_revision" ]] || fail "BUILDKITE_COMMIT must equal checkout HEAD"
checkout_status="$(git status --porcelain --untracked-files=normal)"
[[ -z "$checkout_status" ]] || fail "checkout contains uncommitted files"
source_root="$(git rev-parse --show-toplevel)"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/verification.XXXXXX")"
trap 'rm -rf "$evidence_dir"' EXIT

"$verifier" run --protocol-version 1 --source-root "$source_root" \
  --revision "$source_revision" --policy-sha256 "$policy_sha256" \
  --evidence-dir "$evidence_dir"
receipt="$evidence_dir/receipt.json"
[[ -s "$receipt" && ! -L "$receipt" ]] || fail "verification receipt is missing or invalid"
"$verifier" validate-receipt --protocol-version 1 --receipt "$receipt" \
  --revision "$source_revision" --policy-sha256 "$policy_sha256" --require-pass
cd "$evidence_dir"
buildkite-agent artifact upload "receipt.json"
