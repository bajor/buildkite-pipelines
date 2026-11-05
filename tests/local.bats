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

@test "pre-push hook blocks a failing push and keeps an Entire-style hook chain working" {
  hooks="$(git rev-parse --git-path hooks)"
  # Same shape as Entire's hooks: pre-push execs "$0.pre-entire-brain".
  printf '#!/bin/sh\necho brain-hook\nexec "$0.pre-entire-brain" "$@"\n' > "$hooks/pre-push"
  printf '#!/bin/sh\necho entire-hook "$1" "$(cat)"\n' > "$hooks/pre-push.pre-entire-brain"
  chmod +x "$hooks/pre-push" "$hooks/pre-push.pre-entire-brain"
  printf '#!/bin/sh\nexit "${CI_RESULT:?}"\n' > ci.sh
  chmod +x ci.sh
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh

  CI_RESULT=1 run "$hooks/pre-push" origin < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" != *"brain-hook"* ]]

  CI_RESULT=0 run "$hooks/pre-push" origin <<< "refs/heads/main abc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brain-hook"* ]]
  [[ "$output" == *"entire-hook origin refs/heads/main abc"* ]]
}

@test "refuses to overwrite an existing backup of the previous hook" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\n' > "$hooks/pre-push"
  printf '#!/bin/sh\n' > "$hooks/pre-push.pre-local-ci"
  run "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "installing the pre-push hook twice keeps a single chain" {
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  run "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ ! -e "$(git rev-parse --git-path hooks)/pre-push.pre-local-ci" ]
}
