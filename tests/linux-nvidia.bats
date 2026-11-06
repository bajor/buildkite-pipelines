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

@test "rejects an Apple-only package that resolves on Linux" {
  mkdir mlx-audio
  cat > mlx-audio/pyproject.toml <<'EOF'
[project]
name = "mlx-audio"
version = "0.0.1"
requires-python = ">=3.12"

[tool.uv]
package = false
EOF
  sed -i 's/dependencies = \[\]/dependencies = ["mlx-audio"]/' pyproject.toml
  cat >> pyproject.toml <<'EOF'

[tool.uv.sources]
mlx-audio = { path = "mlx-audio" }
EOF
  # Resolve the synthetic, platform-independent package into the fixture lock.
  source "$PLUGIN_DIR/lib/uv.sh"
  uv="$(install_uv linux-nvidia "$BATS_TEST_TMPDIR")"
  "$uv" lock
  commit_all

  run "$PLUGIN_DIR/checks/linux-nvidia.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Apple-only packages resolved on Linux: mlx-audio"* ]]
}
