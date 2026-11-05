load helpers

write_changelog() {
  printf '# Changelog\n\n## [%s] - 2026-11-05\n\n- Change.\n' "$1" > CHANGELOG.md
}

setup() {
  init_repo
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  write_changelog 0.2.0
  commit_all
  git push -q origin main
  git switch -q -c feature
  unset BUILDKITE_BRANCH BUILDKITE_PULL_REQUEST_BASE_BRANCH BUILDKITE_PIPELINE_DEFAULT_BRANCH GITHUB_BASE_REF GITHUB_HEAD_REF
  export CHANGELOG_BASE_BRANCH=main
}

@test "fails without a CHANGELOG.md" {
  git rm -q CHANGELOG.md
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no CHANGELOG.md"* ]]
}

@test "fails when the newest section is not a version" {
  printf '# Changelog\n\n## [Unreleased]\n\n- Change.\n' > CHANGELOG.md
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found: ## [Unreleased]"* ]]
}

@test "fails on a branch that does not add a higher version than the base" {
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"feature has [0.2.0] and main has [0.2.0]"* ]]

  write_changelog 0.1.9
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 1 ]
}

@test "passes on a branch that adds a higher version" {
  write_changelog 0.10.0
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new version 0.10.0 on feature (0.2.0 on main)"* ]]
}

@test "passes on the branch that adds the first CHANGELOG.md" {
  git switch -q main
  git rm -q CHANGELOG.md
  echo "Plain text." > README.md
  commit_all
  git push -q origin main
  git switch -q feature
  git reset -q --hard main
  write_changelog 0.1.0
  commit_all
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new version 0.1.0 on feature (none on main)"* ]]
}

@test "on the base branch only checks the format" {
  git switch -q main
  run "$PLUGIN_DIR/checks/changelog.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"newest version 0.2.0 on main"* ]]
}
