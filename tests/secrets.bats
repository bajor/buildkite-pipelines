# Downloads gitleaks, so these tests need network access to github.com.
load helpers

setup() {
  init_repo
  echo "print('ok')" > train.py
  commit_all
}

@test "passes when history has no credentials" {
  run "$PLUGIN_DIR/checks/secrets.sh"
  [ "$status" -eq 0 ]
}

@test "fails on a token that was committed and later deleted" {
  # Fake Hugging Face token (hf_ plus 34 letters), split so this file does
  # not itself match secret scanners.
  echo "HF_TOKEN=hf_""kTqWzXbRvNpLmJdHgFsYcUaEoIiQxZtVbN" > settings.txt
  commit_all
  git rm -q settings.txt
  commit_all
  run "$PLUGIN_DIR/checks/secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"leaks found: 1"* ]]
}
