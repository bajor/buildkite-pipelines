load helpers

setup() {
  init_repo
  echo "print('ok')" > train.py
}

@test "passes when only source files are tracked" {
  commit_all
  run "$PLUGIN_DIR/checks/repo-hygiene.sh"
  [ "$status" -eq 0 ]
}

@test "fails when the repository has no commit to inspect" {
  run "$PLUGIN_DIR/checks/repo-hygiene.sh"
  [ "$status" -ne 0 ]
  [[ "$output" != *"No model artifacts"* ]]
}

@test "fails on tracked model weights regardless of extension case" {
  mkdir models
  echo weights > "models/Bielik 4.5B.GGUF"
  commit_all
  run "$PLUGIN_DIR/checks/repo-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"models/Bielik 4.5B.GGUF"* ]]
}

@test "fails on a tracked file larger than 5 MiB" {
  head -c $((5 * 1024 * 1024 + 1)) /dev/zero > data.csv
  commit_all
  run "$PLUGIN_DIR/checks/repo-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"data.csv"* ]]
}
