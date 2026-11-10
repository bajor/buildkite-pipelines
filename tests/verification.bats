load helpers

setup() {
  init_repo
  echo text > README.md
  commit_all
  export BUILDKITE_COMMIT="$(git rev-parse HEAD)"
  verifier="$BATS_TEST_TMPDIR/verifier"
  policy="$BATS_TEST_TMPDIR/policy.sha256"
  printf '%064d\n' 0 > "$policy"
  export FIXTURE_LOG="$BATS_TEST_TMPDIR/calls"
  export FIXTURE_RECEIPT="$BATS_TEST_TMPDIR/uploaded.json"
  cat > "$verifier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURE_LOG"
case "$1" in
  run)
    [[ "${FIXTURE_RUN_STATUS:-0}" == 0 ]] || exit "$FIXTURE_RUN_STATUS"
    while [[ "$1" != --evidence-dir ]]; do shift; done
    [[ "${FIXTURE_NO_RECEIPT:-0}" == 1 ]] || printf '{"fixture":true}\n' > "$2/receipt.json"
    ;;
  validate-receipt) exit "${FIXTURE_VALIDATE_STATUS:-0}" ;;
esac
SH
  chmod +x "$verifier"
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/buildkite-agent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FIXTURE_UPLOAD_STATUS:-0}" == 0 ]] || exit "$FIXTURE_UPLOAD_STATUS"
cp receipt.json "$FIXTURE_RECEIPT"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/buildkite-agent"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "passes revision and policy to the verifier before uploading its accepted receipt" {
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 0 ]
  [ -s "$FIXTURE_RECEIPT" ]
  grep -q -- "--revision $BUILDKITE_COMMIT --policy-sha256 $(cat "$policy")" "$FIXTURE_LOG"
  grep -q '^validate-receipt .* --require-pass$' "$FIXTURE_LOG"
}

@test "fails without a verifier or valid policy before running verification" {
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier.absent" "$policy"
  [ "$status" -eq 1 ]
  printf invalid > "$policy"
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  [ ! -e "$FIXTURE_LOG" ]
}

@test "rejects the wrong revision and uncommitted source" {
  BUILDKITE_COMMIT=wrong run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  echo changed >> README.md
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  [ ! -e "$FIXTURE_LOG" ]
}

@test "propagates verifier failure without uploading" {
  FIXTURE_RUN_STATUS=23 run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 23 ]
  [ ! -e "$FIXTURE_RECEIPT" ]
}

@test "does not treat failed checkout inspection as a clean checkout" {
  export FIXTURE_GIT="$(command -v git)"
  cat > "$BATS_TEST_TMPDIR/bin/git" <<'SH'
#!/usr/bin/env bash
[[ "$1" != status ]] || exit 17
exec "$FIXTURE_GIT" "$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 17 ]
  [ ! -e "$FIXTURE_LOG" ]
}

@test "rejects successful execution without evidence" {
  FIXTURE_NO_RECEIPT=1 run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 1 ]
  [ ! -e "$FIXTURE_RECEIPT" ]
}

@test "propagates rejected receipt and artifact upload failures" {
  FIXTURE_VALIDATE_STATUS=24 run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 24 ]
  [ ! -e "$FIXTURE_RECEIPT" ]
  FIXTURE_UPLOAD_STATUS=25 run "$PLUGIN_DIR/lib/verification.sh" "$verifier" "$policy"
  [ "$status" -eq 25 ]
}

@test "production check ignores candidate verifier and policy path overrides" {
  mkdir -p "$BATS_TEST_TMPDIR/plugin/checks" "$BATS_TEST_TMPDIR/plugin/lib"
  cp "$PLUGIN_DIR/checks/verification.sh" "$BATS_TEST_TMPDIR/plugin/checks/"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$BATS_TEST_TMPDIR/plugin/lib/verification.sh"
  chmod +x "$BATS_TEST_TMPDIR/plugin/lib/verification.sh"
  BUILDKITE_VERIFICATION_EXECUTABLE="$verifier" BUILDKITE_VERIFICATION_POLICY="$policy" \
    run "$BATS_TEST_TMPDIR/plugin/checks/verification.sh"
  [ "$status" -eq 0 ]
  [ "$output" = $'/opt/buildkite-verification/bin/verifier\n/etc/buildkite-verification/policy.sha256' ]
}
