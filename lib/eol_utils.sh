#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Supported Python range and endoflife.date helpers for the Python
# Supported Versions Action. action.yaml and the test suite both source
# this file, so the range below is the single definition of which Python
# minor versions the action can emit.
#
# This library is designed to be sourced. It does not set shell options.

# The supported range, inclusive at both ends. Every other list of
# versions (the static fallback and the live endoflife.date filter) is
# derived from this pair. Adding a new Python minor is a deliberate,
# reviewed change to PYTHON_NEWEST_SUPPORTED; dropping one moves
# PYTHON_OLDEST_SUPPORTED. Both must share the same major version.
PYTHON_OLDEST_SUPPORTED="3.11"
PYTHON_NEWEST_SUPPORTED="3.15"

# Print the supported range as a space-separated list, ascending, for
# example "3.11 3.12 3.13 3.14 3.15". This is the static fallback used
# when network access is unavailable or offline mode is on.
# Returns non-zero if the range pair is malformed.
get_static_python_versions() {
  local oldest="$PYTHON_OLDEST_SUPPORTED"
  local newest="$PYTHON_NEWEST_SUPPORTED"

  if [[ ! "$oldest" =~ ^[0-9]+\.[0-9]+$ || ! "$newest" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid supported Python range '$oldest'..'$newest'" >&2
    return 1
  fi

  local major="${oldest%%.*}"
  local first_minor=$((10#${oldest#*.}))
  local last_minor=$((10#${newest#*.}))

  if [[ "${newest%%.*}" != "$major" || $first_minor -gt $last_minor ]]; then
    echo "Error: invalid supported Python range '$oldest'..'$newest'" >&2
    return 1
  fi

  local minor versions=""
  for ((minor = first_minor; minor <= last_minor; minor++)); do
    versions+="${versions:+ }$major.$minor"
  done
  echo "$versions"
}

# Filter an endoflife.date Python response, read from stdin, to the
# cycles inside the supported range. Major and minor compare
# numerically, so 3.9 < 3.10 < 3.11. Prints the matching cycles as a
# space-separated list, ascending. Returns non-zero when the input is
# not valid JSON or no cycle falls inside the range.
filter_supported_python_cycles() {
  local versions
  versions="$(
    jq -r --arg lo "$PYTHON_OLDEST_SUPPORTED" --arg hi "$PYTHON_NEWEST_SUPPORTED" '
      ($lo | split(".") | map(tonumber)) as $lo_key
      | ($hi | split(".") | map(tonumber)) as $hi_key
      | [ .[] | .cycle | strings | select(test("^[0-9]+\\.[0-9]+$"))
          | {cycle: ., key: (split(".") | map(tonumber))}
          | select(.key >= $lo_key and .key <= $hi_key) ]
      | unique_by(.key) | map(.cycle) | join(" ")
    ' 2>/dev/null
  )" || return 1

  [[ -n "$versions" ]] || return 1
  echo "$versions"
}

# Internal: check if a command exists in PATH.
_eol_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Internal: detect whether curl supports --retry-all-errors (curl ≥ 7.71.0).
_eol_curl_has_retry_all_errors() {
  curl --help 2>/dev/null | grep -q -- '--retry-all-errors'
}

# Fetch the raw endoflife.date Python response and print it.
# Arguments:
#   $1 - timeout in seconds (default: 6)
#   $2 - max retries (default: 2)
# Returns non-zero when curl or jq is missing, the request fails, or the
# response is not a non-empty array of objects carrying a "cycle" key.
fetch_python_eol_data() {
  local timeout="${1:-6}"
  local retries="${2:-2}"

  if ! _eol_has_cmd curl || ! _eol_has_cmd jq; then
    return 1
  fi

  local -a retry_flag=()
  if _eol_curl_has_retry_all_errors; then
    retry_flag=(--retry-all-errors)
  fi

  # Bash before 4.4 treats an empty array as unset under 'set -u', and
  # action.yaml runs with it, so expand the flag only when present.
  local json
  if ! json="$(curl -s --max-time "$timeout" --retry "$retries" ${retry_flag[@]+"${retry_flag[@]}"} \
      'https://endoflife.date/api/python.json' 2>/dev/null)"; then
    return 1
  fi

  if [[ -z "$json" ]] || ! printf '%s\n' "$json" | \
      jq -e 'type=="array" and length>0 and all(.[]; has("cycle"))' >/dev/null 2>&1; then
    return 1
  fi

  printf '%s\n' "$json"
}

# Fetch supported Python versions from endoflife.date, limited to the
# supported range, and print them as a space-separated list.
# Arguments as for fetch_python_eol_data. Returns non-zero on any
# failure (network, invalid JSON, no cycle inside the range).
#
# Per-version EOL refinement is left to check_version_eol() in
# action.yaml, so consumers can still opt in to warn/strip/fail handling
# for a minor that reaches end of life while inside the range.
fetch_eol_aware_versions() {
  local json
  json="$(fetch_python_eol_data "$@")" || return 1
  printf '%s\n' "$json" | filter_supported_python_cycles
}
