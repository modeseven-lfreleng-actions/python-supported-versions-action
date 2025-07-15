<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# 🐍 Extract Python Versions Supported by Project

Parses pyproject.toml and extracts the Python versions supported by the
project. Determines the most recent version supported and provides JSON
representing all supported versions, for use in GitHub matrix jobs.

**Primary Method**: Extracts from `requires-python` constraint
(e.g. `requires-python = ">=3.10"`)
**Fallback Method**: Parses `Programming Language :: Python ::` classifiers

This brings alignment with actions/setup-python behavior while maintaining
compatibility with projects that use explicit version classifiers.

**Dynamic Version Detection with EOL Awareness**: The action automatically
fetches the latest supported Python versions from official sources, filtering
out end-of-life (EOL) versions to ensure supported Python
versions get used. This provides up-to-date, secure version information
without manual updates. Falls back to static definitions when network access
is unavailable.

## python-supported-versions-action

## Usage Example

<!-- markdownlint-disable MD046 -->

```yaml
  - name: "Get project supported Python versions"
    uses: lfreleng-actions/python-supported-versions-action@main
```

<!-- markdownlint-enable MD046 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Variable Name | Description                                             |
| ------------- | ------------------------------------------------------- |
| BUILD_PYTHON  | Most recent Python version supported by project         |
| MATRIX_JSON   | All Python versions supported by project as JSON string |

<!-- markdownlint-enable MD013 -->

## Workflow Output Example

For a Python project with the content below in its pyproject.toml file:

```toml
requires-python = ">=3.10"
readme = "README.md"
license = { text = "Apache-2.0" }
keywords = ["Python", "Tool"]
classifiers = [
  "License :: OSI Approved :: Apache Software License",
  "Operating System :: Unix",
  "Programming Language :: Python",
  "Programming Language :: Python :: 3",
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.10",
]
```

A workflow calling this action will produce the output below:

```console
Found requires-python constraint: >=3.10 💬
Version constraint: >=3.10
Extracted versions from requires-python: 3.10 3.11 3.12 3.13 3.14 💬
Build Python: 3.14 💬
Matrix JSON: {"python-version": ["3.10","3.11","3.12","3.13","3.14"]}
```

## Implementation Details

### Primary Method: requires-python Constraint

The action first attempts to extract the `requires-python` constraint from
pyproject.toml:

```toml
requires-python = ">=3.10"    # Supports 3.10, 3.11, 3.12, 3.13, 3.14
requires-python = ">3.9"      # Supports 3.10, 3.11, 3.12, 3.13, 3.14
requires-python = "==3.11"    # Supports 3.11 specifically
```

The action evaluates the constraint against supported Python versions
(non-EOL) and returns all matching versions.

**Supported constraint formats:**

- `>=X.Y` - Version X.Y and above (most common)
- `>X.Y` - Greater than version X.Y
- `==X.Y` - Exact version X.Y

### Fallback Method: Programming Language Classifiers

If no `requires-python` constraint exists, the action falls back to
parsing explicit version classifiers:

```toml
classifiers = [
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.10",
]
```

### Shared Utility Architecture

The action uses a modular architecture with shared utility functions located
in `lib/eol_utils.sh` and `lib/constraint_utils.sh`. This design eliminates
code duplication between the main action and test scripts, ensuring
consistent behavior and easier maintenance.

**EOL Utilities (`lib/eol_utils.sh`):**

- `fetch_eol_aware_versions()` - Fetches non-EOL Python versions from API
- `check_eol_api_availability()` - Tests API connectivity
- `get_static_python_versions()` - Provides static fallback versions

**Constraint Parsing Utilities (`lib/constraint_utils.sh`):**

- `extract_requires_python_constraint()` - Extracts requires-python from pyproject.toml
- `extract_classifiers_fallback()` - Extracts Python versions from classifiers
- `parse_version_constraint()` - Parses and applies version constraints
- `process_python_constraints()` - Complete constraint processing pipeline
- `generate_matrix_json()` - Creates GitHub Actions matrix JSON
- `validate_version_format()` - Validates version number formats
- `get_build_version()` - Determines latest version for builds

**Benefits:**

- Single source of truth for constraint parsing logic
- Prevents logic drift between action and tests
- Consistent behavior across action and tests
- Easier maintenance and updates
- Improved code quality and reliability
- Comprehensive unit test coverage

### Supported Python Versions

The action dynamically fetches supported Python versions from the
endoflife.date API, filtering out end-of-life versions to ensure
actively maintained Python versions remain available.

**Dynamic Fetching Process:**

1. Fetches EOL data from `https://endoflife.date/api/python.json`
2. Filters out versions that have reached end-of-life
3. Returns Python 3.9+ versions that are still supported
4. Provides real-time security compliance

**Fallback Mechanism:**
If network access is unavailable or the API request fails, the action falls
back to a static definition of supported Python versions:

- Python 3.9
- Python 3.10
- Python 3.11
- Python 3.12
- Python 3.13

This ensures the action remains functional even in environments without
internet access, while providing the most current EOL information
when possible.

## Dynamic Version Fetching with EOL Awareness

The action automatically fetches the latest supported Python versions from
official sources while filtering out end-of-life (EOL) versions. This
ensures
that projects use supported Python versions, improving security
and maintainability.

### How It Works

1. **EOL Data Retrieval**: Fetches Python EOL information from
   `https://endoflife.date/api/python.json` to determine which versions
   are still supported

2. **Version Filtering**: Parses the JSON response to extract:
   - Python version cycles (e.g., "3.9", "3.10", "3.11")
   - End-of-life dates for each version

3. **EOL Comparison**: Compares current date against EOL dates to filter
   out versions that are no longer supported

4. **Version Selection**: Returns Python 3.9+ versions that are:
   - Not end-of-life (still receiving security updates)
   - Actively maintained by the Python core team

### Network Resilience

The action includes robust error handling for network-related issues:

- **Timeout Protection**: Network requests have a configurable timeout with
  retry attempts
- **Graceful Degradation**: Falls back to static versions if the API is
  unavailable
- **No Workflow Failure**: Network issues don't cause the action to fail

### Benefits

- **Always Current**: Automatically discovers new Python versions as
  they're released
- **Security-Focused**: Automatically excludes EOL versions that no longer
  receive security updates
- **No Maintenance**: Eliminates the need for manual version list updates
- **Reliable**: Maintains compatibility with air-gapped environments
- **Performance**: Minimal impact on workflow execution time
- **Compliance**: Helps maintain security compliance by preventing use of
  unsupported Python versions

### Example Output

When dynamic fetching with EOL filtering is successful:

```text
Fetching valid/supported Python versions
Using dynamic-eol-aware Python versions: 3.9 3.10 3.11 3.12 3.13
```

When the endoflife.date API is unavailable:

```text
Fetching valid/supported Python versions
⚠️  API unavailable, using static fallback versions
Using static Python versions: 3.9 3.10 3.11 3.12 3.13
```

## Testing

The action includes comprehensive tests to verify dynamic fetching, EOL
filtering,
and fallback behavior:

### Running Tests

```bash
# Test EOL-aware version filtering
./tests/test_eol_filtering.sh

# Test dynamic version fetching with EOL awareness
./tests/test_dynamic_versions.sh

# Test network fallback behavior
./tests/test_fallback.sh

# Simple end-to-end test
./tests/simple_test.sh

# Run all tests (comprehensive suite)
./tests/run_all_tests.sh
```

### Test Coverage

- **EOL-Aware Filtering**: Verifies correct exclusion of end-of-life Python
  versions
- **Dynamic Version Fetching**: Verifies API calls and version parsing with
  EOL filtering
- **Network Fallback**: Tests behavior when network is unavailable
- **Static EOL Data**: Tests fallback EOL filtering when API is unavailable
- **Version Parsing**: Validates extraction of stable, supported releases
- **JSON Generation**: Ensures output format is correct
- **Error Handling**: Confirms graceful degradation
- **Edge Cases**: Tests date comparison, empty data, and mixed scenarios

### Manual Testing

To manually test the EOL-aware dynamic fetching:

```bash
# Test EOL API endpoint
curl -s "https://endoflife.date/api/python.json" | \
  jq -r '.[] | select(.eol > now) | .cycle'

# Test GitHub tags endpoint with filtering
curl -s \
  "https://api.github.com/repos/python/cpython/tags?per_page=100" | \
grep '"name": "v[0-9]' | \
grep -v -E '(a[0-9]|b[0-9]|rc[0-9])' | \
sed 's/.*"v\([0-9]\+\.[0-9]\+\)\.[0-9]\+".*/\1/' | \
sort -V | uniq | \
awk '$1 >= 3.9'

# Combined test (EOL filtering + GitHub tags)
echo "Testing complete EOL-aware filtering pipeline..."
```

Expected output should include current non-EOL stable Python versions.
As of 2025, this typically includes 3.9, 3.10, 3.11, 3.12, 3.13 (3.8 and
earlier are EOL).

### EOL Status Reference

Current Python EOL schedule (as of 2025):

- **Python 3.8**: EOL October 7, 2024 (excluded)
- **Python 3.9**: EOL October 31, 2025 (included)
- **Python 3.10**: EOL October 31, 2026 (included)
- **Python 3.11**: EOL October 31, 2027 (included)
- **Python 3.12**: EOL October 31, 2028 (included)
- **Python 3.13**: EOL October 31, 2029 (included)

The action automatically updates this information by fetching current EOL data
from endoflife.date, ensuring accuracy without manual intervention.
