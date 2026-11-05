# shellcheck shell=bash
# Sourced by checks that download a tool. Each check owns its version and
# per-platform checksums; this file owns how an archive is fetched and verified.

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

# Downloads a .tar.gz release, refuses it unless its SHA-256 matches, extracts
# one member into dest_dir, and prints that member's path. Each command returns
# explicitly because callers run this in $(...), where set -e does not apply.
# Usage: install_release_binary <url> <expected_sha256> <member> <dest_dir>
install_release_binary() {
  local url="$1" expected_sha256="$2" member="$3" dest_dir="$4"
  local archive="$dest_dir/release.tar.gz"
  curl --fail --silent --show-error --location --output "$archive" "$url" || return 1

  local actual_sha256
  actual_sha256="$(sha256_of "$archive")" || return 1
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "checksum mismatch for $url (got $actual_sha256)" >&2
    return 1
  fi
  tar -xzf "$archive" -C "$dest_dir" "$member" || return 1
  echo "$dest_dir/$member"
}

# Fails with a message naming the check when no checksum is pinned for this
# machine, instead of running an unverified binary.
unsupported_platform() {
  echo "$1: no pinned build for $(uname -s)-$(uname -m)" >&2
  exit 1
}
