load helpers

setup() {
  export BUILDKITE_COMMIT=0123456789abcdef0123456789abcdef01234567
  export BUILDKITE_BUILD_ID=fixture-build
  export BUILDKITE_JOB_ID=fixture-job
  verifier="$BATS_TEST_TMPDIR/verifier"
  policy="$BATS_TEST_TMPDIR/policy.sha256"
  printf '%064d\n' 0 > "$policy"
  cat > "$verifier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$fixture_dir/calls"
[[ -z "${BUILDKITE_AGENT_ACCESS_TOKEN+x}${AWS_SECRET_ACCESS_KEY+x}${GIT_CONFIG_COUNT+x}" ]] || exit 31
[[ "$PATH" == /usr/bin:/bin && "$PWD" == / ]] || exit 32
[[ ! -f "$fixture_dir/fail" ]] || exit 23
SH
  chmod +x "$verifier"
}

@test "requests an exact candidate policy and build job from the backend" {
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "request-and-wait --protocol-version 2 --candidate-revision $BUILDKITE_COMMIT --policy-sha256 $(cat "$policy") --build-id $BUILDKITE_BUILD_ID --job-id $BUILDKITE_JOB_ID" ]
}

@test "missing verifier directory or invalid policy cannot dispatch" {
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier.absent" "$policy"
  [ "$status" -eq 1 ]
  run "$PLUGIN_DIR/lib/verification.sh" "$BATS_TEST_TMPDIR" "$policy"
  [ "$status" -eq 1 ]
  printf invalid > "$policy"
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "missing full revision or build job identity cannot dispatch" {
  BUILDKITE_COMMIT=HEAD run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  BUILDKITE_BUILD_ID= run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  BUILDKITE_JOB_ID= run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "backend failure remains a failure" {
  touch "$BATS_TEST_TMPDIR/fail"
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 23 ]
}

@test "request does not inherit job credentials git configuration or candidate PATH" {
  BUILDKITE_AGENT_ACCESS_TOKEN=fixture AWS_SECRET_ACCESS_KEY=fixture GIT_CONFIG_COUNT=1 \
    run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 0 ]
}

@test "production adapter passes only fixed worker paths" {
  mkdir -p "$BATS_TEST_TMPDIR/plugin/checks" "$BATS_TEST_TMPDIR/plugin/lib"
  cp "$PLUGIN_DIR/checks/verification.sh" "$BATS_TEST_TMPDIR/plugin/checks/"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$BATS_TEST_TMPDIR/plugin/lib/verification.sh"
  chmod +x "$BATS_TEST_TMPDIR/plugin/lib/verification.sh"
  run "$BATS_TEST_TMPDIR/plugin/checks/verification.sh"
  [ "$status" -eq 0 ]
  [ "$output" = $'/opt/buildkite-verification/bin/verifier\n/etc/buildkite-verification/policy.sha256' ]
}

@test "accepts a full SHA-256 candidate hint and rejects ambiguous executable paths" {
  BUILDKITE_COMMIT=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
    run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 0 ]
  run "$PLUGIN_DIR/lib/verification.sh" verifier "$policy"
  [ "$status" -eq 1 ]
  run "$PLUGIN_DIR/lib/verification.sh" /tmp/a=b/verifier "$policy"
  [ "$status" -eq 1 ]
}
