#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Unit tests for constraint_utils.sh shared functions
# This script tests individual functions to ensure they work correctly
# and maintain expected behavior across changes.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ACTION_DIR="$(dirname "$TESTS_DIR")"

# Source the utilities under test
# shellcheck source=../../../lib/constraint_utils.sh
# shellcheck disable=SC1091
source "$ACTION_DIR/lib/constraint_utils.sh"

# Logging functions
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
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

# Test helper function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if eval "$test_command" >/dev/null 2>&1; then
        local actual_exit_code=0
    else
        local actual_exit_code=$?
    fi

    if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
        log_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "$test_name"
        echo "   Expected exit code: $expected_exit_code"
        echo "   Actual exit code:   $actual_exit_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Test helper for output comparison
test_output() {
    local test_name="$1"
    local test_command="$2"
    local expected_output="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local actual_output
    actual_output=$(eval "$test_command" 2>/dev/null)

    if [[ "$actual_output" == "$expected_output" ]]; then
        log_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "$test_name"
        echo "   Expected: '$expected_output'"
        echo "   Actual:   '$actual_output'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Create temporary test files
create_test_file() {
    local content="$1"
    local temp_file
    temp_file=$(mktemp)
    echo "$content" > "$temp_file"
    echo "$temp_file"
}

# Test extract_requires_python_constraint function
test_extract_requires_python_constraint() {
    log_section "Testing extract_requires_python_constraint"

    # Test 1: Basic requires-python constraint
    log_test_start "Basic requires-python constraint"
    local test_file
    test_file=$(create_test_file '[build-system]
requires-python = ">=3.9"')
    test_output "Basic requires-python extraction" \
        "extract_requires_python_constraint '$test_file'" \
        ">=3.9"
    rm -f "$test_file"

    # Test 2: Complex requires-python constraint
    log_test_start "Complex requires-python constraint"
    test_file=$(create_test_file '[build-system]
requires-python = ">=3.9,<3.13"')
    test_output "Complex requires-python extraction" \
        "extract_requires_python_constraint '$test_file'" \
        ">=3.9,<3.13"
    rm -f "$test_file"

    # Test 3: No requires-python constraint (should fail)
    log_test_start "No requires-python constraint"
    test_file=$(create_test_file '[build-system]
name = "test-project"')
    run_test "No requires-python should fail" \
        "extract_requires_python_constraint '$test_file'" \
        1
    rm -f "$test_file"

    # Test 4: Missing file (should fail)
    log_test_start "Missing file"
    run_test "Missing file should fail" \
        "extract_requires_python_constraint '/nonexistent/file.toml'" \
        1

    # Test 5: Poetry [tool.poetry.dependencies].python extraction
    log_test_start "Poetry python dependency extraction"
    test_file=$(create_test_file '[tool.poetry.dependencies]
python = "^3.10"')
    test_output "Poetry python extraction (^3.10)" \
        "extract_requires_python_constraint '$test_file'" \
        "^3.10"
    rm -f "$test_file"
}

# Test extract_classifiers_fallback function
test_extract_classifiers_fallback() {
    log_section "Testing extract_classifiers_fallback"

    # Test 1: Basic classifiers
    log_test_start "Basic Programming Language classifiers"
    local test_file
    test_file=$(create_test_file '[project]
classifiers = [
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
]')
    test_output "Basic classifiers extraction" \
        "extract_classifiers_fallback '$test_file'" \
        "3.9 3.10 3.11"
    rm -f "$test_file"

    # Test 2: No classifiers (should fail)
    log_test_start "No Programming Language classifiers"
    test_file=$(create_test_file '[project]
name = "test-project"')
    run_test "No classifiers should fail" \
        "extract_classifiers_fallback '$test_file'" \
        1
    rm -f "$test_file"
}

# Test classifier filtering in process_python_constraints
test_classifier_filtering() {
    log_section "Testing classifier filtering in process_python_constraints"

    # Test 1: Classifiers with unavailable versions should be filtered
    log_test_start "Classifiers with unavailable versions"
    local test_file
    test_file=$(create_test_file '[project]
classifiers = [
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.14",
    "Programming Language :: Python :: 3.15",
]')

    # Simulate available versions that don't include 3.15
    local available_versions="3.9 3.10 3.11 3.12 3.13 3.14"

    test_output "Classifier filtering" \
        "process_python_constraints '$test_file' '$available_versions'" \
        "3.9 3.10 3.14"

    rm -f "$test_file"

    # Test 2: All classifiers available should pass through
    log_test_start "All classifiers available"
    test_file=$(create_test_file '[project]
classifiers = [
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
]')

    available_versions="3.9 3.10 3.11 3.12 3.13 3.14"

    test_output "All classifiers available" \
        "process_python_constraints '$test_file' '$available_versions'" \
        "3.10 3.11"

    rm -f "$test_file"
}

# Test parse_version_constraint function
test_parse_version_constraint() {
    log_section "Testing parse_version_constraint"

    local available_versions="3.8 3.9 3.10 3.11 3.12 3.13 3.14"

    # Test 1: Greater than or equal constraint
    log_test_start "Greater than or equal constraint"
    test_output ">=3.10 constraint" \
        "parse_version_constraint '>=3.10' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"

    # Test 2: Less than constraint
    log_test_start "Less than constraint"
    test_output "<3.11 constraint" \
        "parse_version_constraint '<3.11' '$available_versions'" \
        "3.8 3.9 3.10"

    # Test 3: Less than or equal constraint
    log_test_start "Less than or equal constraint"
    test_output "<=3.10 constraint" \
        "parse_version_constraint '<=3.10' '$available_versions'" \
        "3.8 3.9 3.10"

    # Test 4: Greater than constraint
    log_test_start "Greater than constraint"
    test_output ">3.9 constraint" \
        "parse_version_constraint '>3.9' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"

    # Test 5: Exact version constraint
    log_test_start "Exact version constraint"
    test_output "==3.10 constraint" \
        "parse_version_constraint '==3.10' '$available_versions'" \
        "3.10"

    # Test 6: Complex constraint
    log_test_start "Complex constraint"
    test_output ">=3.9,<3.12 constraint" \
        "parse_version_constraint '>=3.9,<3.12' '$available_versions'" \
        "3.9 3.10 3.11"

    # Test 7: No matching versions (should fail)
    log_test_start "No matching versions"
    run_test ">=4.0 should fail" \
        "parse_version_constraint '>=4.0' '$available_versions'" \
        1

    # Test 8: Invalid constraint format (should fail)
    log_test_start "Invalid constraint format"
    run_test "Invalid constraint should fail" \
        "parse_version_constraint 'invalid' '$available_versions'" \
        1

    # Test 9: PEP 440 compatible release (~=) without patch
    log_test_start "Compatible release (~=3.10)"
    test_output "~=3.10 constraint" \
        "parse_version_constraint '~=3.10' '$available_versions'" \
        "3.10"

    # Test 10: PEP 440 compatible release (~=) with patch
    log_test_start "Compatible release (~=3.10.1)"
    test_output "~=3.10.1 constraint" \
        "parse_version_constraint '~=3.10.1' '$available_versions'" \
        "3.10"

    # Test 11: Poetry caret (^) without patch
    log_test_start "Caret constraint (^3.10)"
    test_output "^3.10 constraint" \
        "parse_version_constraint '^3.10' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"

    # Test 12: Poetry caret (^) with patch
    log_test_start "Caret constraint (^3.10.1)"
    test_output "^3.10.1 constraint" \
        "parse_version_constraint '^3.10.1' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"

    # Test 13: Wildcard exact (==3.10.*)
    log_test_start "Wildcard exact (==3.10.*)"
    test_output "==3.10.* constraint" \
        "parse_version_constraint '==3.10.*' '$available_versions'" \
        "3.10"

    # Test 14: Exclusion (!=3.10)
    log_test_start "Exclusion (!=3.10)"
    test_output "!=3.10 constraint" \
        "parse_version_constraint '!=3.10' '$available_versions'" \
        "3.8 3.9 3.11 3.12 3.13 3.14"
}

# Test generate_matrix_json function
test_generate_matrix_json() {
    log_section "Testing generate_matrix_json"

    # Test 1: Single version
    log_test_start "Single version JSON generation"
    test_output "Single version JSON" \
        "generate_matrix_json '3.10'" \
        '{"python-version": ["3.10"]}'

    # Test 2: Multiple versions
    log_test_start "Multiple versions JSON generation"
    test_output "Multiple versions JSON" \
        "generate_matrix_json '3.9 3.10 3.11'" \
        '{"python-version": ["3.9","3.10","3.11"]}'

    # Test 3: Empty input
    log_test_start "Empty versions JSON generation"
    test_output "Empty versions JSON" \
        "generate_matrix_json ''" \
        '{"python-version": []}'
}

# Test validate_version_format function
test_validate_version_format() {
    log_section "Testing validate_version_format"

    # Test 1: Valid versions
    log_test_start "Valid version formats"
    run_test "Valid versions should pass" \
        "validate_version_format '3.9 3.10 3.11'" \
        0

    # Test 2: Invalid version format (should fail)
    log_test_start "Invalid version format"
    run_test "Invalid version should fail" \
        "validate_version_format '3.9 invalid 3.11'" \
        1

    # Test 3: Mixed valid and invalid (should fail)
    log_test_start "Mixed valid and invalid versions"
    run_test "Mixed versions should fail" \
        "validate_version_format '3.9 3.10.1 3.11'" \
        1
}

# Test validate_json_format function
test_validate_json_format() {
    log_section "Testing validate_json_format"

    # Test 1: Valid JSON format
    log_test_start "Valid JSON format"
    run_test "Valid JSON should pass" \
        "validate_json_format '{\"python-version\": [\"3.9\",\"3.10\"]}'" \
        0

    # Test 2: Invalid JSON format (should fail)
    log_test_start "Invalid JSON format"
    run_test "Invalid JSON should fail" \
        "validate_json_format '{\"invalid\": [\"3.9\"]}'" \
        1

    # Test 3: Malformed JSON (should fail)
    log_test_start "Malformed JSON"
    run_test "Malformed JSON should fail" \
        "validate_json_format '{\"python-version\": [\"3.9\"'" \
        1
}

# Test get_build_version function
test_get_build_version() {
    log_section "Testing get_build_version"

    # Test 1: Multiple versions
    log_test_start "Multiple versions build selection"
    test_output "Build version selection" \
        "get_build_version '3.9 3.10 3.11'" \
        "3.11"

    # Test 2: Single version
    log_test_start "Single version build selection"
    test_output "Single build version" \
        "get_build_version '3.10'" \
        "3.10"

    # Test 3: Empty input (should fail)
    log_test_start "Empty versions build selection"
    run_test "Empty build version should fail" \
        "get_build_version ''" \
        1
}

# Test process_python_constraints integration function
test_process_python_constraints() {
    log_section "Testing process_python_constraints (Integration)"

    local available_versions="3.9 3.10 3.11 3.12 3.13 3.14"

    # Test 1: requires-python constraint
    log_test_start "Process requires-python constraint"
    local test_file
    test_file=$(create_test_file '[build-system]
requires-python = ">=3.10"')
    test_output "Process requires-python" \
        "process_python_constraints '$test_file' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"
    rm -f "$test_file"

    # Test 2: Fallback to classifiers
    log_test_start "Process fallback to classifiers"
    test_file=$(create_test_file '[project]
classifiers = [
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.11",
]')
    test_output "Process classifiers fallback" \
        "process_python_constraints '$test_file' '$available_versions'" \
        "3.9 3.11"
    rm -f "$test_file"

    # Test 3: No constraints found (should fail)
    log_test_start "Process no constraints found"
    test_file=$(create_test_file '[project]
name = "test-project"')
    run_test "No constraints should fail" \
        "process_python_constraints '$test_file' '$available_versions'" \
        1
    rm -f "$test_file"

    # Test 4: Poetry python constraint via [tool.poetry.dependencies]
    log_test_start "Process Poetry caret constraint"
    test_file=$(create_test_file '[tool.poetry.dependencies]
python = "^3.10"')
    test_output "Process Poetry constraint (^3.10)" \
        "process_python_constraints '$test_file' '$available_versions'" \
        "3.10 3.11 3.12 3.13 3.14"
    rm -f "$test_file"
}

# Helper: create a temporary setup.cfg fixture and echo its path.
create_setup_cfg() {
    local content="$1"
    local d
    d=$(mktemp -d)
    printf '%s\n' "$content" > "$d/setup.cfg"
    echo "$d/setup.cfg"
}

# Test extract_requires_python_setup_cfg
test_extract_requires_python_setup_cfg() {
    log_section "Testing extract_requires_python_setup_cfg"

    log_test_start "Bare value (no quotes)"
    local f
    f=$(create_setup_cfg '[options]
python_requires = >=3.10')
    test_output "Bare >=3.10" \
        "extract_requires_python_setup_cfg '$f'" \
        ">=3.10"
    rm -rf "$(dirname "$f")"

    log_test_start "Double-quoted value"
    f=$(create_setup_cfg '[options]
python_requires = ">=3.11"')
    test_output 'Quoted ">=3.11"' \
        "extract_requires_python_setup_cfg '$f'" \
        ">=3.11"
    rm -rf "$(dirname "$f")"

    log_test_start "Single-quoted value"
    f=$(create_setup_cfg "[options]
python_requires = '==3.12'")
    test_output "Single-quoted ==3.12" \
        "extract_requires_python_setup_cfg '$f'" \
        "==3.12"
    rm -rf "$(dirname "$f")"

    log_test_start "Comma-joined range constraint"
    f=$(create_setup_cfg '[options]
python_requires = >=3.11,<3.13')
    test_output "Range >=3.11,<3.13" \
        "extract_requires_python_setup_cfg '$f'" \
        ">=3.11,<3.13"
    rm -rf "$(dirname "$f")"

    log_test_start "Key absent"
    f=$(create_setup_cfg '[metadata]
name = empty')
    run_test "Missing python_requires should fail" \
        "extract_requires_python_setup_cfg '$f'" \
        1
    rm -rf "$(dirname "$f")"

    log_test_start "Key present but outside [options]"
    f=$(create_setup_cfg '[metadata]
python_requires = >=3.10
[options]
zip_safe = False')
    run_test "python_requires under [metadata] should not match" \
        "extract_requires_python_setup_cfg '$f'" \
        1
    rm -rf "$(dirname "$f")"

    log_test_start "Comment-only file"
    f=$(create_setup_cfg '# nothing to see here')
    run_test "No [options] section should fail" \
        "extract_requires_python_setup_cfg '$f'" \
        1
    rm -rf "$(dirname "$f")"

    log_test_start "Missing file"
    run_test "Nonexistent file should fail" \
        "extract_requires_python_setup_cfg '/nonexistent/setup.cfg'" \
        1
}

# Test extract_classifiers_setup_cfg (modern 'classifiers' + legacy 'classifier')
test_extract_classifiers_setup_cfg() {
    log_section "Testing extract_classifiers_setup_cfg"

    log_test_start "Modern setuptools 'classifiers'"
    local f
    f=$(create_setup_cfg '[metadata]
name = x
classifiers =
    Programming Language :: Python :: 3.10
    Programming Language :: Python :: 3.11
    Programming Language :: Python :: 3.12')
    test_output "Modern classifiers" \
        "extract_classifiers_setup_cfg '$f'" \
        "3.10 3.11 3.12"
    rm -rf "$(dirname "$f")"

    log_test_start "Legacy PBR 'classifier' (singular)"
    f=$(create_setup_cfg '[metadata]
name = legacy
classifier =
    Programming Language :: Python :: 3.11
    Programming Language :: Python :: 3.12
    Programming Language :: Python :: 3.13')
    test_output "Legacy classifier" \
        "extract_classifiers_setup_cfg '$f'" \
        "3.11 3.12 3.13"
    rm -rf "$(dirname "$f")"

    log_test_start "Both keys present, results merged in first-seen order"
    f=$(create_setup_cfg '[metadata]
name = both
classifiers =
    Programming Language :: Python :: 3.12
    Programming Language :: Python :: 3.13
classifier =
    Programming Language :: Python :: 3.11')
    test_output "Merged keys" \
        "extract_classifiers_setup_cfg '$f'" \
        "3.12 3.13 3.11"
    rm -rf "$(dirname "$f")"

    log_test_start "No Python classifiers present"
    f=$(create_setup_cfg '[metadata]
name = nopython
classifiers =
    License :: OSI Approved :: Apache Software License
    Operating System :: OS Independent')
    run_test "Should fail without Python :: X.Y lines" \
        "extract_classifiers_setup_cfg '$f'" \
        1
    rm -rf "$(dirname "$f")"

    log_test_start "Wildcard X.Y.* classifiers ignored"
    # '3.10.*' must NOT be matched as a minor version. The negative
    # lookahead in the Python helper guards against this.
    f=$(create_setup_cfg '[metadata]
name = wildcard
classifiers =
    Programming Language :: Python :: 3.10
    Programming Language :: Python :: 3.10.*')
    test_output "Wildcard ignored" \
        "extract_classifiers_setup_cfg '$f'" \
        "3.10"
    rm -rf "$(dirname "$f")"

    log_test_start "Missing file"
    run_test "Nonexistent file should fail" \
        "extract_classifiers_setup_cfg '/nonexistent/setup.cfg'" \
        1
}

# Test process_python_constraints_setup_cfg high-level wrapper.
test_process_python_constraints_setup_cfg() {
    log_section "Testing process_python_constraints_setup_cfg"

    local available_versions="3.10 3.11 3.12 3.13 3.14"

    log_test_start "python_requires path"
    local f
    f=$(create_setup_cfg '[options]
python_requires = >=3.12')
    test_output "python_requires >=3.12" \
        "process_python_constraints_setup_cfg '$f' '$available_versions'" \
        "3.12 3.13 3.14"
    rm -rf "$(dirname "$f")"

    log_test_start "Classifiers fallback path"
    f=$(create_setup_cfg '[metadata]
name = cls
classifiers =
    Programming Language :: Python :: 3.11
    Programming Language :: Python :: 3.12')
    test_output "Classifiers-only setup.cfg" \
        "process_python_constraints_setup_cfg '$f' '$available_versions'" \
        "3.11 3.12"
    rm -rf "$(dirname "$f")"

    log_test_start "Classifiers with unavailable versions are filtered"
    f=$(create_setup_cfg '[metadata]
name = filter
classifiers =
    Programming Language :: Python :: 3.8
    Programming Language :: Python :: 3.9
    Programming Language :: Python :: 3.12')
    test_output "Only 3.12 remains after filter" \
        "process_python_constraints_setup_cfg '$f' '$available_versions'" \
        "3.12"
    rm -rf "$(dirname "$f")"

    log_test_start "Empty metadata file (should fail)"
    f=$(create_setup_cfg '[metadata]
name = empty')
    run_test "No usable metadata should fail" \
        "process_python_constraints_setup_cfg '$f' '$available_versions'" \
        1
    rm -rf "$(dirname "$f")"
}

# Test detect_metadata_source precedence helper.
test_detect_metadata_source() {
    log_section "Testing detect_metadata_source"

    log_test_start "pyproject.toml wins over setup.cfg"
    local d
    d=$(mktemp -d)
    printf '[project]\nname = "x"\n' > "$d/pyproject.toml"
    printf '[metadata]\nname = x\n' > "$d/setup.cfg"
    test_output "Returns pyproject.toml path" \
        "detect_metadata_source '$d' 2>/dev/null" \
        "$d/pyproject.toml"
    rm -rf "$d"

    log_test_start "setup.cfg used when pyproject.toml absent"
    d=$(mktemp -d)
    printf '[metadata]\nname = x\n' > "$d/setup.cfg"
    test_output "Returns setup.cfg path" \
        "detect_metadata_source '$d' 2>/dev/null" \
        "$d/setup.cfg"
    rm -rf "$d"

    log_test_start "Returns non-zero when neither file exists"
    d=$(mktemp -d)
    run_test "Should fail when no metadata files exist" \
        "detect_metadata_source '$d'" \
        1
    rm -rf "$d"

    log_test_start "Source tag is written to stderr"
    d=$(mktemp -d)
    printf '[project]\nname = "x"\n' > "$d/pyproject.toml"
    local tag
    tag=$(detect_metadata_source "$d" 2>&1 >/dev/null)
    if [[ "$tag" == "pyproject" ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "stderr tag = 'pyproject'"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "Expected stderr tag 'pyproject', got '$tag'"
    fi
    rm -rf "$d"
}

# Main test execution
main() {
    echo -e "${CYAN}"
    echo "🧪 Constraint Utilities Unit Test Suite"
    echo "========================================"
    echo -e "${NC}"

    # Run all test suites
    test_extract_requires_python_constraint
    test_extract_classifiers_fallback
    test_classifier_filtering
    test_parse_version_constraint
    test_generate_matrix_json
    test_validate_version_format
    test_validate_json_format
    test_get_build_version
    test_process_python_constraints
    test_extract_requires_python_setup_cfg
    test_extract_classifiers_setup_cfg
    test_process_python_constraints_setup_cfg
    test_detect_metadata_source

    # Final summary
    log_section "Unit Test Results Summary"

    echo -e "${CYAN}📊 Test Statistics:${NC}"
    echo "   Total Tests: $TOTAL_TESTS"
    echo -e "   ${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "   ${RED}Failed: $FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo ""
        log_success "All unit tests passed! 🎉"
        echo ""
        echo -e "${GREEN}✨ Test Coverage Summary:${NC}"
        echo "   • extract_requires_python_constraint ✅"
        echo "   • extract_classifiers_fallback ✅"
        echo "   • classifier_filtering ✅"
        echo "   • parse_version_constraint ✅"
        echo "   • generate_matrix_json ✅"
        echo "   • validate_version_format ✅"
        echo "   • validate_json_format ✅"
        echo "   • get_build_version ✅"
        echo "   • process_python_constraints ✅"
        echo "   • extract_requires_python_setup_cfg ✅"
        echo "   • extract_classifiers_setup_cfg ✅"
        echo "   • process_python_constraints_setup_cfg ✅"
        echo "   • detect_metadata_source ✅"
        echo ""
        exit 0
    else
        echo ""
        log_error "$FAILED_TESTS unit test(s) failed"
        exit 1
    fi
}

# Run main function
main "$@"
