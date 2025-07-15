#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Shared utility functions for Python version constraint parsing
# This script provides common functionality used by both the main action
# and test scripts to avoid code duplication and ensure consistency.

# Extract requires-python constraint from pyproject.toml
# Usage: extract_requires_python_constraint <pyproject_file>
# Arguments:
#   pyproject_file: Path to pyproject.toml file
# Returns: The requires-python constraint string (without quotes)
# Exit codes: 0 on success, 1 if not found
extract_requires_python_constraint() {
    local pyproject_file="$1"
    local constraint

    if [[ ! -f "$pyproject_file" ]]; then
        return 1
    fi

    # Extract requires-python constraint, avoiding test metadata comments
    constraint=$(grep -o 'requires-python\s*=\s*"[^"]*"' "$pyproject_file" \
                 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' | head -1)

    if [[ -n "$constraint" ]]; then
        printf '%s\n' "$constraint"
        return 0
    else
        return 1
    fi
}

# Extract Programming Language classifiers from pyproject.toml
# Usage: extract_classifiers_fallback <pyproject_file>
# Arguments:
#   pyproject_file: Path to pyproject.toml file
# Returns: Space-separated list of Python versions from classifiers
# Exit codes: 0 on success, 1 if not found
extract_classifiers_fallback() {
    local pyproject_file="$1"
    local classifiers

    if [[ ! -f "$pyproject_file" ]]; then
        return 1
    fi

    # Extract Python versions from Programming Language classifiers
    classifiers=$(grep '"Programming Language :: Python :: [0-9]\+\.[0-9]\+"' \
                  "$pyproject_file" 2>/dev/null | \
                  grep -o '[0-9]\+\.[0-9]\+' | \
                  sort -V | uniq | tr '\n' ' ' | sed 's/ *$//')

    if [[ -n "$classifiers" ]]; then
        printf '%s\n' "$classifiers"
        return 0
    else
        return 1
    fi
}

# Parse version constraint and filter available versions
# Usage: parse_version_constraint <constraint> <available_versions>
# Arguments:
#   constraint: Version constraint string (e.g., ">=3.9", ">=3.9,<3.13")
#   available_versions: Space-separated list of available versions
# Returns: Space-separated list of versions matching the constraint
# Exit codes: 0 on success, 1 on parsing error
parse_version_constraint() {
    local constraint="$1"
    local all_versions="$2"
    local result=''

    # Handle complex constraints with multiple parts (e.g., ">=3.11,<3.13")
    if [[ "$constraint" == *","* ]]; then
        local candidates="$all_versions"

        # Split by comma and process each constraint part
        local IFS=','
        local -a parts
        read -ra parts <<< "$constraint"
        unset IFS


        for part in "${parts[@]}"; do
            # Trim whitespace
            part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local temp_result=''

            case "$part" in
                \>=*)
                    local min_version="${part#>=}"
                    for version in $candidates; do
                        if [[ "$(printf '%s\n%s\n' "$min_version" "$version" | \
                                 sort -V | head -n1)" == "$min_version" ]]; then
                            temp_result="$temp_result $version"
                        fi
                    done
                    ;;
                \>*)
                    local min_version="${part#>}"
                    for version in $candidates; do
                        if [[ "$(printf '%s\n%s\n' "$min_version" "$version" | \
                                 sort -V | tail -n1)" == "$version" && \
                                 "$version" != "$min_version" ]]; then
                            temp_result="$temp_result $version"
                        fi
                    done
                    ;;
                \<=*)
                    local max_version="${part#<=}"
                    for version in $candidates; do
                        if [[ "$(printf '%s\n%s\n' "$max_version" "$version" | \
                                 sort -V | head -n1)" == "$version" ]]; then
                            temp_result="$temp_result $version"
                        fi
                    done
                    ;;
                \<*)
                    local max_version="${part#<}"
                    for version in $candidates; do
                        if [[ "$(printf '%s\n%s\n' "$max_version" "$version" | \
                                 sort -V | tail -n1)" == "$max_version" && \
                                 "$version" != "$max_version" ]]; then
                            temp_result="$temp_result $version"
                        fi
                    done
                    ;;
                ==*)
                    local exact_version="${part#==}"
                    for version in $candidates; do
                        if [[ "$version" == "$exact_version" ]]; then
                            temp_result="$version"
                            break
                        fi
                    done
                    ;;
                *)
                    echo "Warning: Unsupported constraint part: $part" >&2
                    return 1
                    ;;
            esac

            # Update candidates to be the filtered result
            if [[ -n "$temp_result" ]]; then
                candidates=$(echo "$temp_result" | tr ' ' '\n' | grep -v '^$' | \
                           sort -u | tr '\n' ' ' | sed 's/ *$//')
            else
                candidates=''
                break  # No matches found, no point continuing
            fi
        done

        result="$candidates"
    else
        # Handle simple constraints
        case "$constraint" in
            \>=*)
                local min_version="${constraint#>=}"
                for version in $all_versions; do
                    if [[ "$(printf '%s\n%s\n' "$min_version" "$version" | \
                             sort -V | head -n1)" == "$min_version" ]]; then
                        result="$result $version"
                    fi
                done
                ;;
            \>*)
                local min_version="${constraint#>}"
                for version in $all_versions; do
                    if [[ "$(printf '%s\n%s\n' "$min_version" "$version" | \
                             sort -V | tail -n1)" == "$version" && \
                             "$version" != "$min_version" ]]; then
                        result="$result $version"
                    fi
                done
                ;;
            \<=*)
                local max_version="${constraint#<=}"
                for version in $all_versions; do
                    if [[ "$(printf '%s\n%s\n' "$max_version" "$version" | \
                             sort -V | head -n1)" == "$version" ]]; then
                        result="$result $version"
                    fi
                done
                ;;
            \<*)
                local max_version="${constraint#<}"
                for version in $all_versions; do
                    if [[ "$(printf '%s\n%s\n' "$max_version" "$version" | \
                             sort -V | tail -n1)" == "$max_version" && \
                             "$version" != "$max_version" ]]; then
                        result="$result $version"
                    fi
                done
                ;;
            ==*)
                local exact_version="${constraint#==}"
                for version in $all_versions; do
                    if [[ "$version" == "$exact_version" ]]; then
                        result="$version"
                        break
                    fi
                done
                ;;
            *)
                echo "Warning: Unsupported constraint format: $constraint" >&2
                return 1
                ;;
        esac
    fi

    # Clean up, sort, and return result
    result=$(printf '%s\n' "$result" | sed 's/^ *//' | sed 's/ *$//')
    if [[ -n "$result" ]]; then
        # Ensure final result is properly sorted
        result=$(printf '%s\n' "$result" | tr ' ' '\n' | sort -V | tr '\n' ' ' | sed 's/ *$//')
        printf '%s\n' "$result"
        return 0
    else
        return 1
    fi
}

# Generate matrix JSON from space-separated version list
# Usage: generate_matrix_json <versions>
# Arguments:
#   versions: Space-separated list of Python versions
# Returns: JSON string suitable for GitHub Actions matrix
# Exit codes: 0 on success, 1 on error
generate_matrix_json() {
    local versions="$1"
    local json_array=''

    for version in $versions; do
        if [[ -n "$json_array" ]]; then
            json_array="$json_array,\"$version\""
        else
            json_array="\"$version\""
        fi
    done

    printf '{"python-version": [%s]}\n' "$json_array"
}

# Validate that all versions have correct format
# Usage: validate_version_format <versions>
# Arguments:
#   versions: Space-separated list of versions to validate
# Returns: Nothing
# Exit codes: 0 if all valid, 1 if any invalid
validate_version_format() {
    local versions="$1"

    for version in $versions; do
        if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            echo "Invalid version format: '$version'" >&2
            return 1
        fi
    done

    return 0
}

# Validate JSON format (basic validation without external tools)
# Usage: validate_json_format <json_string>
# Arguments:
#   json_string: JSON string to validate
# Returns: Nothing
# Exit codes: 0 if valid, 1 if invalid
validate_json_format() {
    local json="$1"

    if [[ "$json" =~ ^\{\"python-version\":[[:space:]]*\[.*\]\}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get the latest/build version from a list of versions
# Usage: get_build_version <versions>
# Arguments:
#   versions: Space-separated list of Python versions
# Returns: The highest version number
# Exit codes: 0 on success, 1 if no versions provided
get_build_version() {
    local versions="$1"

    if [[ -z "$versions" ]]; then
        return 1
    fi

    printf '%s\n' "$versions" | tr ' ' '\n' | sort -V | tail -1
}

# Process Python version constraints from pyproject.toml
# Usage: process_python_constraints <pyproject_file> <available_versions>
# Arguments:
#   pyproject_file: Path to pyproject.toml file
#   available_versions: Space-separated list of available Python versions
# Returns: Space-separated list of supported Python versions
# Exit codes: 0 on success, 1 on error
process_python_constraints() {
    local pyproject_file="$1"
    local available_versions="$2"
    local python_versions=""
    local requires_python=""
    local classifiers=""

    # Extract requires-python constraint
    if requires_python=$(extract_requires_python_constraint "$pyproject_file"); then
        if python_versions=$(parse_version_constraint "$requires_python" \
                           "$available_versions"); then
            # Clean up whitespace
            python_versions=$(echo "$python_versions" | \
                            sed 's/^ *//' | sed 's/ *$//')
        fi
    fi

    # Fall back to classifiers if no versions from requires-python
    if [[ -z "$python_versions" ]]; then
        if classifiers=$(extract_classifiers_fallback "$pyproject_file"); then
            # Intersect classifiers with available_versions
            python_versions=$(printf '%s\n' "$classifiers" | tr ' ' '\n' | \
                            grep -Fx -f <(printf '%s\n' "$available_versions" | tr ' ' '\n') | \
                            tr '\n' ' ' | sed 's/ *$//')
        fi
    fi

    # Validate results
    if [[ -n "$python_versions" ]]; then
        if validate_version_format "$python_versions"; then
            # Sort and return
            python_versions=$(printf '%s\n' "$python_versions" | \
                            sort -V | tr '\n' ' ' | sed 's/ *$//')
            printf '%s\n' "$python_versions"
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}
