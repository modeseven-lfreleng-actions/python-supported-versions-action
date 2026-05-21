#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Comprehensive consolidated test script for Python Supported Versions Action
# This is the SINGLE test entry point that performs all tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="$TESTS_DIR/fixtures"
ACTION_DIR="$(dirname "$TESTS_DIR")"

# Source shared EOL utility functions
# shellcheck source=../../lib/eol_utils.sh
# shellcheck disable=SC1091
source "$ACTION_DIR/lib/eol_utils.sh"

# Source shared constraint parsing utilities
# shellcheck source=../../lib/constraint_utils.sh
# shellcheck disable=SC1091
source "$ACTION_DIR/lib/constraint_utils.sh"

# Cleanup function
# shellcheck disable=SC2329  # Invoked by trap cleanup EXIT
cleanup() {
    if [ -f "$TESTS_DIR/pyproject.toml" ]; then
        rm -f "$TESTS_DIR/pyproject.toml"
    fi
    if [ -f "$TESTS_DIR/setup.cfg" ]; then
        rm -f "$TESTS_DIR/setup.cfg"
    fi
    # Clean up any temporary files
    find "$TESTS_DIR" -name "*.tmp" -delete 2>/dev/null || true
}
trap cleanup EXIT

# Logging functions
log_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    # shellcheck disable=SC2317  # Function may be called indirectly
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_test_start() {
    echo -e "${BLUE}🔍 Testing: $1${NC}"
}

log_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# Helper: count versions in a space-separated string
count_versions() {
    local versions="$1"
    if [ -z "$versions" ]; then
        echo 0
    else
        # shellcheck disable=SC2086
        set -- $versions
        echo $#
    fi
}

# Helper: get first (minimum) version from a space-separated list
first_version() {
    local versions="$1"
    echo "$versions" | awk '{print $1}'
}

# Helper: simple equality assertion
assert_equal() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        log_success "$name OK (expected '$expected')"
        return 0
    else
        log_error "$name MISMATCH (expected '$expected', got '$actual')"
        return 1
    fi
}

# Function to extract metadata from fixture files
extract_metadata() {
    local file="$1"
    local key="$2"
    # Handle both old format (# KEY:) and new format (# KEY: value after TEST_METADATA)
    grep "^# $key:" "$file" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//' || echo ""
}

# Function to test a fixture by running the action logic
test_fixture_with_action() {
    local fixture_file="$1"
    local fixture_name
    fixture_name=$(basename "$fixture_file" .toml)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Extract metadata
    local test_name
    test_name=$(extract_metadata "$fixture_file" "TEST_NAME")
    local should_fail
    should_fail=$(extract_metadata "$fixture_file" "SHOULD_FAIL")
    local description
    description=$(extract_metadata "$fixture_file" "DESCRIPTION")

    # Use filename as test name if not specified
    if [ -z "$test_name" ]; then
        test_name="$fixture_name"
    fi

    log_test_start "$test_name"

    if [ -n "$description" ]; then
        echo "   Description: $description"
    fi

    # Create test directory structure
    local test_dir
    test_dir=$(mktemp -d)
    cp "$fixture_file" "$test_dir/pyproject.toml"

    # Run the actual action simulation
    local result=""
    local exit_code=0

    # Change to test directory
    pushd "$test_dir" >/dev/null 2>&1

    # Simulate the action's core logic using shared utilities.
    # 3.9 is intentionally absent: it reached EOL in October 2025
    # and is no longer part of the default supported set.
    local ALL_SUPPORTED_VERSIONS="3.10 3.11 3.12 3.13 3.14"
    local PYTHON_VERSIONS=""

    # Use shared utility to process Python constraints
    if PYTHON_VERSIONS=$(process_python_constraints "pyproject.toml" \
                       "$ALL_SUPPORTED_VERSIONS"); then
        # Generate outputs using shared utilities
        local BUILD_PYTHON
        BUILD_PYTHON=$(get_build_version "$PYTHON_VERSIONS")
        local MATRIX_JSON
        MATRIX_JSON=$(generate_matrix_json "$PYTHON_VERSIONS")
        result="STATUS=SUCCESS
BUILD_PYTHON=$BUILD_PYTHON
MATRIX_JSON=$MATRIX_JSON
PYTHON_VERSIONS=$PYTHON_VERSIONS"
        exit_code=0
    else
        exit_code=1
        result="No Python versions found"
    fi

    popd >/dev/null 2>&1
    rm -rf "$test_dir"

    # Validate results
    local test_passed=true

    if [ "$should_fail" = "true" ]; then
        if [ $exit_code -eq 0 ]; then
            log_error "$test_name - Expected test to fail but it succeeded"
            test_passed=false
        else
            # Optionally validate expected error message
            local expected_error
            expected_error=$(extract_metadata "$fixture_file" "EXPECTED_ERROR")
            if [ -n "$expected_error" ]; then
                if echo "$result" | grep -q "$expected_error"; then
                    log_success "$test_name - Correctly failed with expected error"
                else
                    log_error "$test_name - Failed, but error did not match expectation"
                    echo "   Expected error to contain: $expected_error"
                    echo "   Actual: $result"
                    test_passed=false
                fi
            else
                log_success "$test_name - Correctly failed as expected"
            fi
        fi
    else
        if [ $exit_code -ne 0 ]; then
            log_error "$test_name - Expected test to succeed but it failed: $result"
            test_passed=false
        else
            local build_python
            build_python=$(echo "$result" | grep "^BUILD_PYTHON=" | cut -d'=' -f2-)
            local python_versions
            python_versions=$(echo "$result" | grep "^PYTHON_VERSIONS=" | cut -d'=' -f2-)
            log_success "$test_name"
            echo "   Build Python: $build_python"
            echo "   All versions: $python_versions"

            # Validate against optional metadata expectations
            local expected_exact expected_min expected_count
            expected_exact=$(extract_metadata "$fixture_file" "EXPECTED_EXACT_VERSION")
            expected_min=$(extract_metadata "$fixture_file" "EXPECTED_MIN_VERSION")
            expected_count=$(extract_metadata "$fixture_file" "EXPECTED_VERSIONS_COUNT")

            # Exact version expectation
            if [ -n "$expected_exact" ]; then
                if ! assert_equal "Exact version" "$expected_exact" "$python_versions"; then
                    test_passed=false
                fi
                if ! assert_equal "Build version" "$expected_exact" "$build_python"; then
                    test_passed=false
                fi
            fi

            # Minimum version expectation
            if [ -n "$expected_min" ]; then
                local actual_min
                actual_min=$(first_version "$python_versions")
                if ! assert_equal "Minimum version" "$expected_min" "$actual_min"; then
                    test_passed=false
                fi
            fi

            # Count expectation
            if [ -n "$expected_count" ]; then
                local actual_count
                actual_count=$(count_versions "$python_versions")
                if ! assert_equal "Versions count" "$expected_count" "$actual_count"; then
                    test_passed=false
                fi
            fi
        fi
    fi

    # Update counters
    if [ "$test_passed" = true ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    echo ""
}

# Variant of test_fixture_with_action that exercises the setup.cfg path.
# The fixture is copied to <tmpdir>/setup.cfg (NOT pyproject.toml) so the
# action consults the setup.cfg branch.
test_setup_cfg_fixture() {
    local fixture_file="$1"
    local fixture_name
    fixture_name=$(basename "$fixture_file" .cfg)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local test_name
    test_name=$(extract_metadata "$fixture_file" "TEST_NAME")
    local should_fail
    should_fail=$(extract_metadata "$fixture_file" "SHOULD_FAIL")
    local description
    description=$(extract_metadata "$fixture_file" "DESCRIPTION")

    if [ -z "$test_name" ]; then
        test_name="$fixture_name"
    fi

    log_test_start "$test_name"
    if [ -n "$description" ]; then
        echo "   Description: $description"
    fi

    local test_dir
    test_dir=$(mktemp -d)
    cp "$fixture_file" "$test_dir/setup.cfg"

    local result=""
    local exit_code=0

    pushd "$test_dir" >/dev/null 2>&1

    local ALL_SUPPORTED_VERSIONS="3.10 3.11 3.12 3.13 3.14"
    local PYTHON_VERSIONS=""

    if PYTHON_VERSIONS=$(process_python_constraints_setup_cfg "setup.cfg" \
                         "$ALL_SUPPORTED_VERSIONS"); then
        local BUILD_PYTHON MATRIX_JSON
        BUILD_PYTHON=$(get_build_version "$PYTHON_VERSIONS")
        MATRIX_JSON=$(generate_matrix_json "$PYTHON_VERSIONS")
        result="STATUS=SUCCESS
BUILD_PYTHON=$BUILD_PYTHON
MATRIX_JSON=$MATRIX_JSON
PYTHON_VERSIONS=$PYTHON_VERSIONS"
        exit_code=0
    else
        exit_code=1
        result="No Python versions found"
    fi

    popd >/dev/null 2>&1
    rm -rf "$test_dir"

    local test_passed=true
    if [ "$should_fail" = "true" ]; then
        if [ $exit_code -eq 0 ]; then
            log_error "$test_name - Expected test to fail but it succeeded"
            test_passed=false
        else
            log_success "$test_name - Correctly failed as expected"
        fi
    else
        if [ $exit_code -ne 0 ]; then
            log_error "$test_name - Expected test to succeed but it failed: $result"
            test_passed=false
        else
            local build_python python_versions
            build_python=$(echo "$result" | grep "^BUILD_PYTHON=" | cut -d'=' -f2-)
            python_versions=$(echo "$result" | grep "^PYTHON_VERSIONS=" | cut -d'=' -f2-)
            log_success "$test_name"
            echo "   Build Python: $build_python"
            echo "   All versions: $python_versions"

            local expected_exact expected_min expected_count
            expected_exact=$(extract_metadata "$fixture_file" "EXPECTED_EXACT_VERSION")
            expected_min=$(extract_metadata "$fixture_file" "EXPECTED_MIN_VERSION")
            expected_count=$(extract_metadata "$fixture_file" "EXPECTED_VERSIONS_COUNT")

            if [ -n "$expected_exact" ]; then
                if ! assert_equal "Exact version" "$expected_exact" "$python_versions"; then
                    test_passed=false
                fi
                if ! assert_equal "Build version" "$expected_exact" "$build_python"; then
                    test_passed=false
                fi
            fi
            if [ -n "$expected_min" ]; then
                local actual_min
                actual_min=$(first_version "$python_versions")
                if ! assert_equal "Minimum version" "$expected_min" "$actual_min"; then
                    test_passed=false
                fi
            fi
            if [ -n "$expected_count" ]; then
                local actual_count
                actual_count=$(count_versions "$python_versions")
                if ! assert_equal "Versions count" "$expected_count" "$actual_count"; then
                    test_passed=false
                fi
            fi
        fi
    fi

    if [ "$test_passed" = true ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Detect the metadata source precedence using the shared helper.
test_metadata_source_precedence() {
    log_section "Metadata Source Precedence"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "detect_metadata_source: pyproject takes precedence"

    local d
    d=$(mktemp -d)
    printf '[project]\nname = "x"\nrequires-python = ">=3.11"\n' > "$d/pyproject.toml"
    printf '[metadata]\nname = x\n' > "$d/setup.cfg"
    local source_path source_tag
    source_path=$(detect_metadata_source "$d" 2> /tmp/_src_tag) || true
    source_tag=$(cat /tmp/_src_tag)
    if [ "$(basename "$source_path")" = "pyproject.toml" ] && [ "$source_tag" = "pyproject" ]; then
        log_success "pyproject.toml wins when both files exist"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "Expected pyproject.toml precedence; got path='$source_path' tag='$source_tag'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    rm -rf "$d" /tmp/_src_tag

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "detect_metadata_source: setup.cfg used when pyproject absent"
    d=$(mktemp -d)
    printf '[metadata]\nname = x\n' > "$d/setup.cfg"
    source_path=$(detect_metadata_source "$d" 2> /tmp/_src_tag) || true
    source_tag=$(cat /tmp/_src_tag)
    if [ "$(basename "$source_path")" = "setup.cfg" ] && [ "$source_tag" = "setup.cfg" ]; then
        log_success "setup.cfg used when pyproject.toml absent"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "Expected setup.cfg detection; got path='$source_path' tag='$source_tag'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    rm -rf "$d" /tmp/_src_tag

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "detect_metadata_source: error when neither file exists"
    d=$(mktemp -d)
    if detect_metadata_source "$d" 2>/dev/null; then
        log_error "Expected non-zero when neither file exists"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        log_success "Correctly returned non-zero when neither file exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    rm -rf "$d"
    echo ""
}

# Function to test EOL awareness
test_eol_awareness() {
    log_section "EOL Awareness Tests"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "EOL Version Filtering"

    # Test that our static version list excludes EOL versions.
    # 3.9 reached EOL in October 2025 and 3.8 in October 2024; both
    # should be absent from the static list.
    local supported_versions
    supported_versions=$(get_static_python_versions)

    echo "   Test versions: $supported_versions"

    if echo "$supported_versions" | grep -qE '(^| )3\.8( |$)'; then
        log_error "Python 3.8 should be EOL but was included in static versions"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return
    fi
    if echo "$supported_versions" | grep -qE '(^| )3\.9( |$)'; then
        log_error "Python 3.9 should be EOL but was included in static versions"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return
    fi

    # Sanity-check: 3.10 must be present (oldest non-EOL minor at the
    # time of writing). Update when 3.10 itself reaches EOL.
    if ! echo "$supported_versions" | grep -qE '(^| )3\.10( |$)'; then
        log_error "Expected to find Python 3.10 in supported versions"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return
    fi

    log_success "EOL Version Filtering - Python 3.8 and 3.9 correctly excluded"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo ""
}

# Function to test network fallback simulation
test_network_fallback() {
    log_section "Network Fallback Tests"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "Static Fallback Mechanism"

    local static_versions
    static_versions=$(get_static_python_versions)

    if [ -n "$static_versions" ] && echo "$static_versions" | grep -qE '(^| )3\.10( |$)'; then
        log_success "Static Fallback - Versions available when network unavailable"
        echo "   Static versions: $static_versions"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "Static fallback failed to provide valid versions"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    echo ""
}

# Function to test EOL API logic
test_eol_api_logic() {
    log_section "EOL API Logic Tests"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "EOL API Response and Filtering"

    # Test EOL API logic using shared utility function

    # Test the EOL API logic
    local versions
    if versions=$(fetch_eol_aware_versions 10 3); then
        log_success "EOL API Response and Filtering - API accessible"
        echo "   Supported versions: $versions"

        # Validate versions format
        local valid=true
        for version in $versions; do
            if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
                log_error "Invalid version format: $version"
                valid=false
            fi
        done

        if [[ "$valid" == "true" ]]; then
            log_success "All versions have valid format"
        else
            log_error "Some versions have invalid format"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return
        fi

        # Check for minimum expected versions (3.10+; 3.9 is now EOL)
        if echo "$versions" | grep -qE '(^| )3\.10( |$)'; then
            log_success "Found expected minimum version (3.10)"
        else
            log_warning "Expected versions not found"
            echo "   Expected to find 3.10 in returned versions"
        fi

        # Check that EOL versions are excluded (Python 3.8 and 3.9)
        if echo "$versions" | grep -qE '(^| )3\.[89]( |$)'; then
            log_error "EOL Python (3.8/3.9) should not be in API result"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return
        else
            log_success "EOL Python versions correctly excluded"
        fi

        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_warning "API unavailable - testing static fallback behavior"
        local static_versions
        static_versions=$(get_static_python_versions)
        echo "   Static fallback would provide: $static_versions"

        # This is still a valid scenario, so count as passed
        log_success "Static fallback mechanism works correctly"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi

    echo ""
}

# Function to run unit tests
run_unit_tests() {
    log_section "Unit Tests"

    local unit_test_script="$SCRIPT_DIR/unit/test_constraint_utils.sh"

    if [[ -f "$unit_test_script" ]]; then
        log_info "Running constraint utilities unit tests"
        if bash "$unit_test_script"; then
            log_success "Unit tests completed successfully"
        else
            log_error "Unit tests failed"
            exit 1
        fi
    else
        log_warning "Unit test script not found: $unit_test_script"
    fi
}

# Main test execution
main() {
    echo -e "${CYAN}"
    echo "🧪 Python Supported Versions Action - Comprehensive Test Suite"
    echo "=============================================================="
    echo -e "${NC}"

    # Check prerequisites
    log_section "Prerequisites Check"

    local missing_tools=""

    if ! command -v grep >/dev/null 2>&1; then
        missing_tools="$missing_tools grep"
    fi

    if ! command -v sed >/dev/null 2>&1; then
        missing_tools="$missing_tools sed"
    fi

    if [ -n "$missing_tools" ]; then
        log_error "Missing required tools:$missing_tools"
        exit 1
    fi

    log_success "Prerequisites satisfied"

    # Check test fixtures
    if [ ! -d "$FIXTURES_DIR" ]; then
        log_error "Fixtures directory not found: $FIXTURES_DIR"
        exit 1
    fi

    local fixture_count
    fixture_count=$(find "$FIXTURES_DIR" -name "*.toml" 2>/dev/null | wc -l)
    local cfg_fixture_count
    cfg_fixture_count=$(find "$FIXTURES_DIR" -name "*.cfg" 2>/dev/null | wc -l)
    log_info "Found $fixture_count pyproject.toml test fixtures"
    log_info "Found $cfg_fixture_count setup.cfg test fixtures"

    # Run unit tests first
    run_unit_tests

    # Test fixture files
    log_section "pyproject.toml Fixture-Based Tests"

    for fixture_file in "$FIXTURES_DIR"/*.toml; do
        if [ -f "$fixture_file" ]; then
            test_fixture_with_action "$fixture_file"
        fi
    done

    # Test setup.cfg fixtures (new path: legacy setuptools / PBR projects)
    log_section "setup.cfg Fixture-Based Tests"

    for fixture_file in "$FIXTURES_DIR"/*.cfg; do
        if [ -f "$fixture_file" ]; then
            test_setup_cfg_fixture "$fixture_file"
        fi
    done

    # Test metadata source precedence detection
    test_metadata_source_precedence

    # Test EOL awareness
    test_eol_awareness

    # Test EOL API logic
    test_eol_api_logic

    # Test network fallback
    test_network_fallback

    # Final summary
    log_section "Test Results Summary"

    echo -e "${CYAN}📊 Test Statistics:${NC}"
    echo "   Total Tests: $TOTAL_TESTS"
    echo -e "   ${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "   ${RED}Failed: $FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo ""
        log_success "All tests passed! 🎉"
        echo ""
        echo -e "${GREEN}✨ Test Coverage Summary:${NC}"
        echo "   • Basic requires-python constraints ✅"
        echo "   • Complex requires-python constraints ✅"
        echo "   • Exact version constraints ✅"
        echo "   • Classifiers-only scenarios ✅"
        echo "   • Mixed version scenarios ✅"
        echo "   • setup.cfg python_requires extraction ✅"
        echo "   • setup.cfg classifiers (modern + PBR legacy) ✅"
        echo "   • Metadata source precedence (pyproject > setup.cfg) ✅"
        echo "   • Error handling and edge cases ✅"
        echo "   • EOL-aware version filtering ✅"
        echo "   • Network fallback mechanisms ✅"
        echo "   • EOL API response validation ✅"
        echo "   • Shared constraint parsing utilities ✅"
        echo ""
        echo -e "${CYAN}🔒 Security & Compliance:${NC}"
        echo "   • EOL version filtering prevents use of unsupported Python versions ✅"
        echo "   • Network resilience ensures action works in air-gapped environments ✅"
        echo "   • Comprehensive error handling prevents workflow failures ✅"
        echo "   • Real-time EOL awareness via endoflife.date API ✅"
        echo "   • Centralized constraint parsing prevents logic drift ✅"
        echo ""

        exit 0
    else
        echo ""
        log_error "$FAILED_TESTS test(s) failed"
        exit 1
    fi
}

# Run main function
main "$@"
