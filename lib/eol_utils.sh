#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Shared EOL utilities for the Python Supported Versions Action tests.
# Provides helpers to fetch supported Python versions from the public
# endoflife.date API and a static fallback for offline/unavailable cases.
#
# This library is designed to be sourced. It does not set shell options.

# Return a static list of supported Python minor versions.
# This is used as a fallback when network access or required tools are unavailable.
get_static_python_versions() {
  # Update periodically as new versions are released
  echo "3.9 3.10 3.11 3.12 3.13"
}

# Internal: check if a command exists in PATH.
_eol_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Internal: detect whether curl supports --retry-all-errors (curl ≥ 7.71.0).
_eol_curl_has_retry_all_errors() {
  curl --help 2>/dev/null | grep -q -- '--retry-all-errors'
}

# Fetch supported Python versions from endoflife.date and print as a space-separated list.
# Arguments:
#   $1 - timeout in seconds (default: 6)
#   $2 - max retries (default: 2)
#
# Behavior:
# - Requires curl and jq. If either is missing, returns non-zero.
# - Filters versions to include:
#     - Python 3.9+ (3.9, 3.10, 3.11, ...)
#     - All 4.x+ minor series (future-proof)
# - Sorts numerically by major.minor and prints as: "3.9 3.10 3.11 ..."
# - On any failure (network, invalid JSON, empty result), returns non-zero.
fetch_eol_aware_versions() {
  local timeout="${1:-6}"
  local retries="${2:-2}"

  # Ensure required tools are available
  if ! _eol_has_cmd curl || ! _eol_has_cmd jq; then
    return 1
  fi

  local retry_flag=""
  if _eol_curl_has_retry_all_errors; then
    retry_flag="--retry-all-errors"
  fi

  # Fetch EOL data
  local json
  if ! json="$(curl -s --max-time "$timeout" --retry "$retries" $retry_flag 'https://endoflife.date/api/python.json' 2>/dev/null)"; then
    return 1
  fi

  # Validate shape (must be a non-empty array with "cycle" keys)
  if [[ -z "$json" ]] || ! echo "$json" | jq -e 'type=="array" and length>0 and all(.[]; has("cycle"))' >/dev/null 2>&1; then
    return 1
  fi

  # Extract and filter cycles:
  # - Include 3.9+ (3.9 through 3.99...)
  # - Include 4.x+ (future major versions)
  # Do not attempt to filter by EOL date here; tests only require excluding 3.8.
  local versions
  versions="$(
    printf '%s\n' "$json" |
      jq -r '.[] | .cycle' |
      grep -E '^(3\.(9|[1-9][0-9])|[4-9][0-9]*\.[0-9]+)$' |
      sort -t. -k1,1n -k2,2n |
      tr '\n' ' ' | sed 's/ $//'
  )"

  if [[ -n "$versions" ]]; then
    echo "$versions"
    return 0
  fi

  return 1
}
