# These tests download uv and resolve packages, so they need network.
load helpers

setup() {
  init_repo
}

use_fixture() {
  cp -R "$PLUGIN_DIR/tests/fixtures/$1/." .
  commit_all
}

@test "passes a project locked for Apple Silicon" {
  use_fixture apple-silicon-project
  run "$PLUGIN_DIR/checks/apple-silicon.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready for Apple Silicon"* ]]
}

@test "fails a project that does not require macOS arm64 in uv.lock" {
  # Its only dependency is limited to macOS arm64, so the marker text appears
  # in uv.lock without being a required environment.
  use_fixture platform-dependency-project
  run "$PLUGIN_DIR/checks/apple-silicon.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"required-environments"* ]]
}

@test "fails a project that locks a CUDA-only package for macOS arm64" {
  use_fixture cuda-package-project
  run "$PLUGIN_DIR/checks/apple-silicon.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CUDA-only packages in the macOS arm64 lock: nvidia-ml-py"* ]]
}

@test "fails NVIDIA-only code and configuration, and accepts allowed lines" {
  use_fixture apple-silicon-project
  mkdir -p src configs
  cat > src/train.py <<'EOF'
model = model.cuda()
args = TrainingArguments(fp16=True, optim="paged_adamw_8bit")
device = "cuda" if torch.cuda.is_available() else "mps"  # apple-silicon: allow
EOF
  printf 'mixed_precision: fp16\n' > configs/accelerate.yaml
  commit_all
  run "$PLUGIN_DIR/checks/apple-silicon.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/train.py:1:"* ]]
  [[ "$output" == *"Use bf16=True on Apple Silicon"* ]]
  [[ "$output" == *'Use optim="adamw_torch"'* ]]
  [[ "$output" == *"configs/accelerate.yaml:1:"* ]]
  [[ "$output" != *"src/train.py:3:"* ]]
}
