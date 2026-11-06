# These tests download uv and resolve the fixture lock.
load helpers

setup() {
  init_repo
  cp -R "$PLUGIN_DIR/tests/fixtures/apple-silicon-project/." .
  sed -i "s/sys_platform == 'darwin' and platform_machine == 'arm64'/sys_platform == 'linux' and platform_machine == 'x86_64'/g" pyproject.toml
  sed -i "s/platform_machine == 'arm64' and sys_platform == 'darwin'/platform_machine == 'x86_64' and sys_platform == 'linux'/g" uv.lock
  commit_all
}

@test "accepts a Linux x86-64 locked project" {
  run "$PLUGIN_DIR/checks/linux-nvidia.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready for Linux x86-64"* ]]
}

@test "rejects a lock without a required Linux target" {
  sed -i '/^required-markers = \[/,/^\]/d' uv.lock
  run "$PLUGIN_DIR/checks/linux-nvidia.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"require Linux x86-64"* ]]
}
