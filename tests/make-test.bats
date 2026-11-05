load helpers

setup() {
  init_repo
}

@test "fails without a Makefile" {
  run "$PLUGIN_DIR/checks/make-test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Makefile"* ]]
}

@test "fails when the Makefile has no test target" {
  printf 'build:\n\ttrue\n' > Makefile
  run "$PLUGIN_DIR/checks/make-test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no test target"* ]]
}

@test "fails when make test fails" {
  printf 'test:\n\techo running-tests\n\tfalse\n' > Makefile
  run "$PLUGIN_DIR/checks/make-test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"running-tests"* ]]
}

@test "passes when make test passes" {
  printf 'test:\n\techo all-tests-passed\n' > Makefile
  run "$PLUGIN_DIR/checks/make-test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all-tests-passed"* ]]
}
