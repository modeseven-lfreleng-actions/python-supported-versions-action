#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Shared utility functions for End-of-Life (EOL) API operations
# This script provides common functionality used by both the main action
# and test scripts to avoid code duplication.

# Fetch EOL-aware Python versions from endoflife.date API
# Usage: fetch_eol_aware_versions [timeout] [retries]
# Arguments:
#   timeout: Network timeout in seconds (default: 10)
#   retries: Maximum retry attempts (default: 3)
# Returns: Space-separated list of non-EOL Python versions (3.9+)
# Exit codes: 0 on success, 1 on failure
fetch_eol_aware_versions() {
    local eol_data current_date versions
    local TIMEOUT="${1:-10}"
    local RETRIES="${2:-3}"

    if eol_data=$(curl -s --max-time "$TIMEOUT" --retry "$RETRIES" \
      'https://endoflife.date/api/python.json' 2>/dev/null); then

      current_date=$(date +%Y-%m-%d)

      # Extract non-EOL Python versions (3.9+) using jq to parse JSON
      versions=$(printf '%s\n' "$eol_data" | \
        jq -r --arg date "$current_date" '
          .[] |
          select(.eol != null and .eol > $date and (.cycle | test("^3\\.(9|[1-9][0-9])$"))) |
          .cycle
        ' | sort -V | tr '\n' ' ' | sed 's/ $//')

      if [[ -n "$versions" ]]; then
        printf '%s\n' "$versions"
        return 0
      else
        return 1
      fi
    else
      return 1
    fi
}

# Check if EOL API is accessible
# Usage: check_eol_api_availability [timeout] [retries]
# Arguments:
#   timeout: Network timeout in seconds (default: 5)
#   retries: Maximum retry attempts (default: 1)
# Exit codes: 0 if accessible, 1 if not accessible
check_eol_api_availability() {
    local TIMEOUT="${1:-5}"
    local RETRIES="${2:-1}"

    curl -s --max-time "$TIMEOUT" --retry "$RETRIES" \
      --head 'https://endoflife.date/api/python.json' \
      >/dev/null 2>&1
}

# Get static fallback Python versions
# Usage: get_static_python_versions
# Returns: Space-separated list of static Python versions
get_static_python_versions() {
    echo "3.9 3.10 3.11 3.12 3.13"
}
