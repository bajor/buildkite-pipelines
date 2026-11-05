#!/usr/bin/env bash
# Scans every commit for credentials such as Hugging Face, cloud, and API
# tokens, using a pinned gitleaks release whose archive checksum is verified
# before it runs. A secret removed in a later commit still fails the check,
# because it remains readable in git history and must be rotated.
set -euo pipefail

readonly gitleaks_version="8.30.1"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) platform="linux_x64" expected_sha256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb" ;;
  Linux-aarch64) platform="linux_arm64" expected_sha256="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080" ;;
  Darwin-arm64) platform="darwin_arm64" expected_sha256="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5" ;;
  *)
    echo "secrets: no pinned gitleaks build for $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitleaks.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
archive="$work_dir/gitleaks.tar.gz"

curl --fail --silent --show-error --location --output "$archive" \
  "https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_version}/gitleaks_${gitleaks_version}_${platform}.tar.gz"
actual_sha256="$(sha256_of "$archive")"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "secrets: gitleaks archive checksum mismatch (got $actual_sha256)" >&2
  exit 1
fi
tar -xzf "$archive" -C "$work_dir" gitleaks

"$work_dir/gitleaks" git --redact --no-banner --exit-code 1 .
