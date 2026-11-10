#!/usr/bin/env bash
set -euo pipefail

verifier="${1:?worker verifier required}"
policy_file="${2:?worker policy file required}"

fail() {
  echo "verification request: $*" >&2
  exit 1
}

[[ -f "$verifier" && -x "$verifier" ]] || fail "worker-owned verifier is unavailable"
[[ -f "$policy_file" ]] || fail "worker-owned policy pin is unavailable"
policy_sha256="$(<"$policy_file")"
[[ "$policy_sha256" =~ ^[a-f0-9]{64}$ ]] || fail "invalid policy SHA-256"
[[ "${BUILDKITE_COMMIT:-}" =~ ^[a-f0-9]{40}$ ]] || fail "full candidate commit required"
[[ -n "${BUILDKITE_BUILD_ID:-}" && -n "${BUILDKITE_JOB_ID:-}" ]] || fail "build and job identity required"

exec /usr/bin/env -i PATH=/usr/bin:/bin "$verifier" request-and-wait \
  --protocol-version 2 --candidate-revision "$BUILDKITE_COMMIT" \
  --policy-sha256 "$policy_sha256" --build-id "$BUILDKITE_BUILD_ID" \
  --job-id "$BUILDKITE_JOB_ID"
