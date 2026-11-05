#!/usr/bin/env bash
# Fails when the checked-out commit tracks model weights, datasets, or other
# large files. Fine-tuning repositories keep those on external storage, and a
# file committed once stays in git history even after it is deleted.
set -euo pipefail

readonly max_file_bytes=$((5 * 1024 * 1024))
readonly artifact_pattern='\.(safetensors|gguf|ggml|bin|pt|pth|ckpt|onnx|h5|keras|pkl|pickle|npy|npz|parquet|arrow|tfrecord)$'
shopt -s nocasematch

# Written to a file first: a failing process substitution would not stop the
# script, and the check would pass without reading any files.
tree_listing="$(mktemp "${TMPDIR:-/tmp}/repo-hygiene.XXXXXX")"
trap 'rm -f "$tree_listing"' EXIT
git ls-tree -r -l -z HEAD > "$tree_listing"

failures=0
# Each -z entry is "<mode> <type> <object> <padded size>\t<path>".
while IFS= read -r -d '' entry; do
  meta="${entry%%$'\t'*}"
  path="${entry#*$'\t'}"
  size="${meta##* }"
  [[ "$meta" == *" blob "* ]] || continue

  if [[ "$path" =~ $artifact_pattern ]]; then
    echo "Model or dataset artifact is tracked: $path"
    failures=$((failures + 1))
  elif ((size > max_file_bytes)); then
    echo "File exceeds $((max_file_bytes / 1024 / 1024)) MiB: $path ($size bytes)"
    failures=$((failures + 1))
  fi
done < "$tree_listing"

if ((failures > 0)); then
  echo "Keep weights, datasets, and adapters on external storage and remove them from git." >&2
  exit 1
fi
echo "No model artifacts or files over $((max_file_bytes / 1024 / 1024)) MiB are tracked."
