load helpers

setup() {
  init_repo
  echo "Plain text." > README.md
  commit_all
  unset BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_PIPELINE BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK
}

@test "runs the named check" {
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=repo-hygiene run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No model artifacts"* ]]
}

@test "rejects a path-like check name even when its target exists" {
  # checks/../lib/upload-pipeline.sh exists, so only the name guard stops it.
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=../lib/upload-pipeline run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown checks entry '../lib/upload-pipeline'; available:"*"repo-hygiene"* ]]
}

@test "rejects a step that sets both options" {
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=repo-hygiene \
    BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_PIPELINE=python-ml \
    run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one plugin option"* ]]
}
