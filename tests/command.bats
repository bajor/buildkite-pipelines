load helpers

setup() {
  init_repo
  echo "Plain text." > README.md
  commit_all
  unset BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_PIPELINE BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK
}

@test "runs the named check" {
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=docs-style run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No em-dashes"* ]]
}

@test "rejects an unknown or path-like check name and lists the available ones" {
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=../hooks/command run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 1 ]
  [[ "$output" == *"available: docs-style"* ]]
}

@test "rejects a step that sets both options" {
  BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_CHECK=docs-style \
    BUILDKITE_PLUGIN_BUILDKITE_PIPELINES_PIPELINE=python-ml \
    run "$PLUGIN_DIR/hooks/command"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one plugin option"* ]]
}
