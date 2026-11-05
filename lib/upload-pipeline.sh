#!/usr/bin/env bash
# Uploads a pipeline template after replacing __PLUGIN__ with the plugin
# reference the uploading step used. Generated steps therefore load this
# plugin at the same location and version tag as the step that created them.
set -euo pipefail

template="$1"
readonly placeholder="__PLUGIN__"

# BUILDKITE_PLUGINS is the JSON list of the current step's plugins, each an
# object keyed by its reference, e.g.
# [{"https://github.com/bajor/buildkite-pipelines#v1.0.0":{"pipeline":"python-ml"}}].
# Option values are lowercase words, so the first quoted string naming this
# repository is the reference.
reference_pattern='"([^"]*/buildkite-pipelines(#[^"]*)?)"'
if [[ ! "${BUILDKITE_PLUGINS:-}" =~ $reference_pattern ]]; then
  echo "buildkite-pipelines: cannot find this plugin's reference in BUILDKITE_PLUGINS" >&2
  exit 1
fi
plugin_reference="${BASH_REMATCH[1]}"

content="$(<"$template")"
# The replacement stays unquoted because bash before 5.2 keeps the quotes
# literally; disabling patsub_replacement stops bash 5.2+ from expanding "&".
shopt -u patsub_replacement 2>/dev/null || true
printf '%s\n' "${content//"$placeholder"/$plugin_reference}" | buildkite-agent pipeline upload
