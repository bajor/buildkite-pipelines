PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Creates an empty git repository in a temporary directory and enters it.
init_repo() {
  cd "$BATS_TEST_TMPDIR"
  git init -q -b main repo
  cd repo
  git config user.email test@example.com
  git config user.name test
}

commit_all() {
  git add -A
  git commit -q -m test
}
