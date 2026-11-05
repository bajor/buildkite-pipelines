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

@test "pre-push hook skips the local run on a branch without the command" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\necho previous-hook "$1"\n' > "$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  "$PLUGIN_DIR/bin/install-pre-push-hook" scripts/ci-local.sh

  run "$hooks/pre-push" origin < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/ci-local.sh is not on this branch"* ]]
  [[ "$output" == *"previous-hook origin"* ]]
}

@test "refuses to overwrite an existing backup of the previous hook" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\n' > "$hooks/pre-push"
  printf '#!/bin/sh\n' > "$hooks/pre-push.pre-local-ci"
  run "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "re-installing updates an installed hook in place and keeps the chain" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\necho previous-hook\n' > "$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  # An older installed hook: same marker, outdated body.
  printf '#!/bin/sh\n# local-ci pre-push hook\nexit 1\n' > "$hooks/pre-push"

  run "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated pre-push hook"* ]]
  grep -q "only deletes refs" "$hooks/pre-push"
  [ -e "$hooks/pre-push.pre-local-ci" ]
  [ ! -e "$hooks/pre-push.pre-local-ci.pre-local-ci" ]
}

@test "a push that only deletes refs skips the CI run and still feeds the previous hook" {
  hooks="$(git rev-parse --git-path hooks)"
  printf '#!/bin/sh\necho previous-hook "$(cat)"\n' > "$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  printf '#!/bin/sh\necho ci-ran\nexit 1\n' > ci.sh
  chmod +x ci.sh
  "$PLUGIN_DIR/bin/install-pre-push-hook" ci.sh
  zero=0000000000000000000000000000000000000000
  sha=1111111111111111111111111111111111111111

  run "$hooks/pre-push" origin <<< "(delete) $zero refs/heads/old $sha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"only deletes refs"* ]]
  [[ "$output" != *"ci-ran"* ]]
  [[ "$output" == *"previous-hook (delete) $zero refs/heads/old $sha"* ]]

  run "$hooks/pre-push" origin <<< "(delete) $zero refs/heads/old $sha
refs/heads/main $sha refs/heads/main $zero"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci-ran"* ]]

  run "$hooks/pre-push" origin <<< "unparseable line"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ci-ran"* ]]
}
