# shellcheck shell=bash
# Sourced by checks that need uv. Owns the pinned uv version and checksums.
# shellcheck source=lib/install-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/install-release.sh"

readonly uv_version="0.13.1"

# Downloads the pinned uv into dest_dir and prints its path. $1 names the
# calling check in the error for an unsupported platform.
install_uv() {
  local check="$1" dest_dir="$2" target expected_sha256
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) target="x86_64-unknown-linux-gnu" expected_sha256="eadd9d27c134ab5ac1ffd4473b97a741407f3ea238288f03121fc4deddf90220" ;;
    Linux-aarch64) target="aarch64-unknown-linux-gnu" expected_sha256="9041c73c99fdc5892cf128140beb354eca9231d502068cc36e6cb53a8e59ad14" ;;
    Darwin-arm64) target="aarch64-apple-darwin" expected_sha256="cfe454573412ff7380d15fc7dae5997ab53ffce72fce0a78e91ddbc84001acd2" ;;
    *) unsupported_platform "$check" ;;
  esac
  install_release_binary \
    "https://github.com/astral-sh/uv/releases/download/${uv_version}/uv-${target}.tar.gz" \
    "$expected_sha256" "uv-${target}/uv" "$dest_dir"
}
