load helpers

reference="https://github.com/bajor/buildkite-pipelines#v1.2.3"

setup() {
  # Stub agent that records the uploaded pipeline instead of contacting Buildkite.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/buildkite-agent" <<EOF
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/uploaded.yml"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/buildkite-agent"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "every uploaded step references the uploader's plugin version" {
  export BUILDKITE_PLUGINS='[{"github.com/buildkite-plugins/entire-buildkite-plugin":null},{"'"$reference"'":{"pipeline":"python-ml"}}]'
  run "$PLUGIN_DIR/lib/upload-pipeline.sh" "$PLUGIN_DIR/pipelines/python-ml.yml"
  [ "$status" -eq 0 ]
  [ "$(grep -c "__PLUGIN__" "$BATS_TEST_TMPDIR/uploaded.yml")" -eq 0 ]
  steps="$(grep -c "check:" "$BATS_TEST_TMPDIR/uploaded.yml")"
  [ "$(grep -cF "\"$reference\":" "$BATS_TEST_TMPDIR/uploaded.yml")" -eq "$steps" ]
}

@test "fails without uploading when the plugin reference is missing" {
  export BUILDKITE_PLUGINS='[{"github.com/buildkite-plugins/entire-buildkite-plugin":null}]'
  run "$PLUGIN_DIR/lib/upload-pipeline.sh" "$PLUGIN_DIR/pipelines/python-ml.yml"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/uploaded.yml" ]
}

@test "Linux NVIDIA template uploads its own check at the pinned plugin version" {
  export BUILDKITE_PLUGINS='[{"'"$reference"'":{"pipeline":"python-ml-nvidia"}}]'
  run "$PLUGIN_DIR/lib/upload-pipeline.sh" "$PLUGIN_DIR/pipelines/python-ml-nvidia.yml"
  [ "$status" -eq 0 ]
  grep -q 'check: linux-nvidia' "$BATS_TEST_TMPDIR/uploaded.yml"
  [ "$(grep -cF "\"$reference\":" "$BATS_TEST_TMPDIR/uploaded.yml")" -eq 6 ]
}
