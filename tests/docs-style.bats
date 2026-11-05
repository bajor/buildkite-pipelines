load helpers

setup() {
  init_repo
  echo "Plain text, no dashes." > README.md
}

@test "fails on an em-dash in hand-written Markdown" {
  printf 'Model \xe2\x80\x94 weights\n' > docs.md
  commit_all
  run "$PLUGIN_DIR/checks/docs-style.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs.md:1"* ]]
}

@test "fails when git cannot read the repository" {
  rm -rf .git
  printf 'Model \xe2\x80\x94 weights\n' > docs.md
  run "$PLUGIN_DIR/checks/docs-style.sh"
  [ "$status" -ne 0 ]
  [[ "$output" != *"No em-dashes"* ]]
}

@test "ignores Markdown generated under .entire/" {
  mkdir .entire
  printf 'Guide \xe2\x80\x94 Brain\n' > .entire/agent-guide.md
  commit_all
  run "$PLUGIN_DIR/checks/docs-style.sh"
  [ "$status" -eq 0 ]
}
