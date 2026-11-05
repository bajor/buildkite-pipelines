load helpers

setup() {
  init_repo
}

@test "passes without running anything when there are no Python files" {
  run "$PLUGIN_DIR/checks/python.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Python files"* ]]
}

@test "fails when Python code is not a uv project" {
  echo "print('hi')" > train.py
  echo "torch" > requirements.txt
  commit_all
  run "$PLUGIN_DIR/checks/python.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit: pyproject.toml uv.lock"* ]]
  [[ "$output" == *"remove: requirements.txt"* ]]
}

# The tests below download uv, Python, ruff, and pytest, so they need network.

@test "passes a project whose lint and tests pass" {
  cp -R "$PLUGIN_DIR/tests/fixtures/python-project/." .
  commit_all
  run "$PLUGIN_DIR/checks/python.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed"* ]]
}

@test "fails a project with a lint error" {
  cp -R "$PLUGIN_DIR/tests/fixtures/python-project/." .
  printf 'import os\n' >> tests/test_addition.py
  commit_all
  run "$PLUGIN_DIR/checks/python.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"F401"* ]]
}

@test "fails when uv.lock no longer matches pyproject.toml" {
  cp -R "$PLUGIN_DIR/tests/fixtures/python-project/." .
  sed -i.bak 's/"pytest>=8"/"pytest>=8", "iniconfig>=2"/' pyproject.toml
  commit_all
  run "$PLUGIN_DIR/checks/python.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs to be updated"* ]]
}
