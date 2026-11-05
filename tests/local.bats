load helpers

setup() {
  init_repo
  echo "Plain text." > README.md
  commit_all
}

# run-local runs the secrets check, which downloads gitleaks.
@test "run-local runs every check and fails when one of them fails" {
  echo weights > model.gguf
  commit_all
  run "$PLUGIN_DIR/bin/run-local" python-ml
  [ "$status" -eq 1 ]
  [[ "$output" == *"--- secrets"* ]]
  [[ "$output" == *"--- python"* ]]
  [[ "$output" == *"Failed: repo-hygiene"* ]]
}

@test "pre-push hook blocks a push when the command fails and chains to the previous hook" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\necho previous-hook "$1"\n' > "$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  printf '#!/bin/sh\nexit "${CI_RESULT:?}"\n' > ci.sh
  chmod +x ci.sh
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh

  CI_RESULT=1 run "$hooks/pre-push" origin
  [ "$status" -eq 1 ]
  [[ "$output" != *"previous-hook"* ]]

  CI_RESULT=0 run "$hooks/pre-push" origin
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous-hook origin"* ]]
}

@test "installing the pre-push hook twice keeps a single chain" {
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  run "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ ! -e "$(git rev-parse --git-path hooks)/pre-push.pre-local-ci" ]
}
