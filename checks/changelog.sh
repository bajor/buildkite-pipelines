#!/usr/bin/env bash
# Keeps CHANGELOG.md releasable:
#   1. It exists, and its newest section is a version heading,
#      `## [X.Y.Z]` optionally followed by ` - YYYY-MM-DD`, which release
#      automation reads to tag vX.Y.Z.
#   2. On any branch other than the base branch, that version is higher than
#      the newest version on the base branch, so every change adds a release.
# The base branch is CHANGELOG_BASE_BRANCH, else the pull request base
# (BUILDKITE_PULL_REQUEST_BASE_BRANCH, GITHUB_BASE_REF), else the pipeline's
# default branch, else main.
set -euo pipefail

readonly changelog="CHANGELOG.md"
readonly version_heading='^## \[([0-9]+\.[0-9]+\.[0-9]+)\]( - [0-9]{4}-[0-9]{2}-[0-9]{2})?$'

fail() {
  echo "changelog: $*" >&2
  exit 1
}

# Prints the version of the first `## [` heading on stdin, or nothing.
newest_version() {
  local heading
  heading="$(grep -m1 '^## \[' || true)"
  if [[ "$heading" =~ $version_heading ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

[[ -f "$changelog" ]] || fail "no $changelog; add one with a '## [0.1.0] - YYYY-MM-DD' section."
version="$(newest_version <"$changelog")"
if [[ -z "$version" ]]; then
  fail "the newest section must start with '## [X.Y.Z] - YYYY-MM-DD'; found: $(grep -m1 '^## ' "$changelog" || echo none)"
fi

pull_request_base="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-}"
base="${CHANGELOG_BASE_BRANCH:-${pull_request_base:-${GITHUB_BASE_REF:-${BUILDKITE_PIPELINE_DEFAULT_BRANCH:-main}}}}"
branch="${BUILDKITE_BRANCH:-${GITHUB_HEAD_REF:-$(git rev-parse --abbrev-ref HEAD)}}"
if [[ "$branch" == "$base" ]]; then
  echo "$changelog: newest version $version on $base."
  exit 0
fi

git fetch --quiet origin "$base"
base_version=""
# The branch that adds the first CHANGELOG.md has nothing to compare against.
if git cat-file -e "FETCH_HEAD:$changelog" 2>/dev/null; then
  base_version="$(git show "FETCH_HEAD:$changelog" | newest_version)"
fi
if [[ -n "$base_version" ]]; then
  highest="$(printf '%s\n%s\n' "$base_version" "$version" | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)"
  if [[ "$version" == "$base_version" || "$highest" != "$version" ]]; then
    fail "add a section above [$base_version] with a higher version; $branch has [$version] and $base has [$base_version]."
  fi
fi
echo "$changelog: new version $version on $branch (${base_version:-none} on $base)."
