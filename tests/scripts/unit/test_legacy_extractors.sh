#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Unit tests for the legacy setup.cfg / setup.py extractors and the
# process_python_constraints_layered helper.

# Do NOT enable `set -e`: many of these tests deliberately invoke functions
# that return non-zero, then assert against $?.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ACTION_DIR="$(dirname "$TESTS_DIR")"

# shellcheck source=../../../lib/constraint_utils.sh
# shellcheck disable=SC1091
source "$ACTION_DIR/lib/constraint_utils.sh"

log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }
log_test()    { echo -e "${BLUE}🔍 Testing: $1${NC}"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$expected" == "$actual" ]]; then
        log_success "$name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "$name"
        echo "   Expected: '$expected'"
        echo "   Actual:   '$actual'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

assert_rc() {
    local name="$1" expected="$2" actual="$3"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$expected" -eq "$actual" ]]; then
        log_success "$name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "$name (expected rc=$expected, got rc=$actual)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

AVAILABLE="3.9 3.10 3.11 3.12 3.13 3.14"

test_setup_cfg() {
    log_section "extract_setup_cfg_*"

    local d
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
name = foo
python_requires = >=3.10
classifiers =
    License :: OSI Approved :: Apache Software License
    Programming Language :: Python :: 3.10
    Programming Language :: Python :: 3.11
    Programming Language :: Python :: 3.12

[options]
packages = find:
EOF

    log_test "setup.cfg python_requires (underscore)"
    assert_eq "python_requires" ">=3.10" \
        "$(extract_setup_cfg_requires_python "$d/setup.cfg")"

    log_test "setup.cfg classifiers"
    assert_eq "classifiers" "3.10 3.11 3.12" \
        "$(extract_setup_cfg_classifiers "$d/setup.cfg")"

    rm -rf "$d"

    # Hyphen variant + quoted constraint
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
name = bar
python-requires = ">=3.9,<3.13"
EOF
    log_test "setup.cfg python-requires (hyphen, quoted)"
    assert_eq "python-requires hyphen" ">=3.9,<3.13" \
        "$(extract_setup_cfg_requires_python "$d/setup.cfg")"
    rm -rf "$d"

    # python_requires under [options] (setuptools declarative config).
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
name = qux

[options]
python_requires = >=3.11
packages = find:
EOF
    log_test "setup.cfg python_requires under [options]"
    assert_eq "python_requires options" ">=3.11" \
        "$(extract_setup_cfg_requires_python "$d/setup.cfg")"
    rm -rf "$d"

    # Missing key
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
name = baz
EOF
    log_test "setup.cfg with no python_requires returns rc=1"
    extract_setup_cfg_requires_python "$d/setup.cfg" >/dev/null 2>&1
    assert_rc "no python_requires rc" 1 $?
    rm -rf "$d"
}

test_setup_py() {
    log_section "extract_setup_py_*"

    local d
    d=$(mktemp -d)
    cat > "$d/setup.py" <<'EOF'
from setuptools import setup
setup(
    name="foo",
    python_requires=">=3.9,<3.13",
    classifiers=[
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
)
EOF

    log_test "setup.py python_requires (double quotes)"
    assert_eq "py python_requires" ">=3.9,<3.13" \
        "$(extract_setup_py_requires_python "$d/setup.py")"

    log_test "setup.py classifiers"
    assert_eq "py classifiers" "3.9 3.10 3.11" \
        "$(extract_setup_py_classifiers "$d/setup.py")"

    rm -rf "$d"

    # Single-quoted
    d=$(mktemp -d)
    cat > "$d/setup.py" <<'EOF'
from setuptools import setup
setup(name='bar', python_requires='>=3.10')
EOF
    log_test "setup.py python_requires (single quotes)"
    assert_eq "py python_requires single" ">=3.10" \
        "$(extract_setup_py_requires_python "$d/setup.py")"
    rm -rf "$d"
}

test_layered() {
    log_section "process_python_constraints_layered"

    # 1) pyproject wins over setup.cfg
    local d
    d=$(mktemp -d)
    cat > "$d/pyproject.toml" <<'EOF'
[project]
requires-python = ">=3.11"
EOF
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
python_requires = >=3.9
EOF
    log_test "layered: pyproject takes priority"
    local out
    out=$(process_python_constraints_layered "$d" "$AVAILABLE")
    assert_eq "pyproject versions" "3.11 3.12 3.13 3.14" "$(echo "$out" | sed -n '1p')"
    assert_eq "pyproject source" "requires-python" "$(echo "$out" | sed -n '2p')"
    rm -rf "$d"

    # 2) setup.cfg-only with python_requires
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
python_requires = >=3.10
EOF
    log_test "layered: setup.cfg requires-python only"
    out=$(process_python_constraints_layered "$d" "$AVAILABLE")
    assert_eq "setup.cfg versions" "3.10 3.11 3.12 3.13 3.14" "$(echo "$out" | sed -n '1p')"
    assert_eq "setup.cfg source" "setup-cfg-requires" "$(echo "$out" | sed -n '2p')"
    rm -rf "$d"

    # 3) setup.cfg classifiers fallback (no python_requires)
    d=$(mktemp -d)
    cat > "$d/setup.cfg" <<'EOF'
[metadata]
classifiers =
    Programming Language :: Python :: 3.10
    Programming Language :: Python :: 3.11
EOF
    log_test "layered: setup.cfg classifiers fallback"
    out=$(process_python_constraints_layered "$d" "$AVAILABLE")
    assert_eq "setup.cfg classifiers versions" "3.10 3.11" "$(echo "$out" | sed -n '1p')"
    assert_eq "setup.cfg classifiers source" "setup-cfg-classifiers" "$(echo "$out" | sed -n '2p')"
    rm -rf "$d"

    # 4) setup.py-only with python_requires
    d=$(mktemp -d)
    cat > "$d/setup.py" <<'EOF'
from setuptools import setup
setup(python_requires=">=3.12")
EOF
    log_test "layered: setup.py requires-python only"
    out=$(process_python_constraints_layered "$d" "$AVAILABLE")
    assert_eq "setup.py versions" "3.12 3.13 3.14" "$(echo "$out" | sed -n '1p')"
    assert_eq "setup.py source" "setup-py-requires" "$(echo "$out" | sed -n '2p')"
    rm -rf "$d"

    # 5) setup.py classifiers fallback
    d=$(mktemp -d)
    cat > "$d/setup.py" <<'EOF'
from setuptools import setup
setup(classifiers=["Programming Language :: Python :: 3.13"])
EOF
    log_test "layered: setup.py classifiers fallback"
    out=$(process_python_constraints_layered "$d" "$AVAILABLE")
    assert_eq "setup.py classifiers versions" "3.13" "$(echo "$out" | sed -n '1p')"
    assert_eq "setup.py classifiers source" "setup-py-classifiers" "$(echo "$out" | sed -n '2p')"
    rm -rf "$d"

    # 6) Empty directory: nothing declared at all
    d=$(mktemp -d)
    log_test "layered: empty dir returns rc=1"
    process_python_constraints_layered "$d" "$AVAILABLE" >/dev/null 2>&1
    assert_rc "empty dir rc" 1 $?
    rm -rf "$d"

    # 7) Directory with unrelated content but no python metadata
    d=$(mktemp -d)
    echo "hello" > "$d/README.md"
    log_test "layered: dir with no python metadata returns rc=1"
    process_python_constraints_layered "$d" "$AVAILABLE" >/dev/null 2>&1
    assert_rc "no metadata rc" 1 $?
    rm -rf "$d"
}

main() {
    echo -e "${CYAN}"
    echo "🧪 Legacy Extractors Unit Test Suite"
    echo "===================================="
    echo -e "${NC}"

    test_setup_cfg
    test_setup_py
    test_layered

    log_section "Summary"
    echo "   Total:  $TOTAL_TESTS"
    echo -e "   ${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "   ${RED}Failed: $FAILED_TESTS${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All legacy extractor tests passed! 🎉"
        exit 0
    else
        log_error "$FAILED_TESTS test(s) failed"
        exit 1
    fi
}

main "$@"
