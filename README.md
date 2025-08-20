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
out end-of-life (EOL) versions to ensure projects use supported Python versions.
This provides up-to-date, secure version information without manual updates.
If the network call fails, the action will continue with a warning and rely
solely on the constraints found in pyproject.toml.

## python-supported-versions-action

## Basic Usage Example

Assuming your Python project code exists in the current working directory
of your Github workflow:

<!-- markdownlint-disable MD046 -->

```yaml
  - name: "Get project supported Python versions"
    uses: lfreleng-actions/python-supported-versions-action@main
```

<!-- markdownlint-enable MD046 -->

## Inputs

<!-- markdownlint-disable MD013 -->

| Variable Name     | Description                                             | Required | Default |
| ----------------- | ------------------------------------------------------- | -------- | ------- |
| path_prefix       | Directory location containing project code              | false    | '.'     |
| network_timeout   | Network timeout in seconds for API calls               | false    | '6'     |
| max_retries       | Number of retry attempts for API calls                 | false    | '2'     |
| eol_behaviour     | How to handle EOL Python versions: warn\|strip\|fail   | false    | 'warn'  |
| offline_mode      | Disable network lookups and use internal version list | false | 'false' |

<!-- markdownlint-enable MD013 -->

## EOL (End-of-Life) Python Version Handling

The action automatically detects when Python versions in your project's
constraints have reached end-of-life (EOL) status and handles them according
to the `eol_behaviour` input:

### eol_behaviour Options

- **warn** (default): Displays warning messages for EOL versions but includes
  them in the output matrix. This allows existing workflows to continue
  running while alerting you to upgrade.

- **strip**: Displays warning messages for EOL versions and removes them from
  the output matrix. This ensures matrix jobs run against supported
  Python versions.

- **fail**: Displays error messages for EOL versions and exits the action with
  status code 1, stopping the workflow. This enforces strict compliance with
  supported Python versions.

### Warning and Error Messages

EOL versions generate messages in both the action console output and the
GitHub Step Summary:

**Warn/Strip Mode:**

```text
Warning: Python 3.8 became unsupported/EOL on date: 2024-10-07 ⚠️
```

**Fail Mode:**

```text
Error: Python 3.8 became unsupported/EOL on date: 2024-10-07 🛑
```

### Usage Examples

**Warn about EOL versions (default):**

```yaml
- name: "Get Python versions with EOL warnings"
  uses: lfreleng-actions/python-supported-versions-action@main
  with:
    eol_behaviour: 'warn'
```

**Strip EOL versions from matrix:**

```yaml
- name: "Get supported Python versions"
  uses: lfreleng-actions/python-supported-versions-action@main
  with:
    eol_behaviour: 'strip'
```

**Fail on EOL versions:**

```yaml
- name: "Enforce supported Python versions"
  uses: lfreleng-actions/python-supported-versions-action@main
  with:
    eol_behaviour: 'fail'
```

## Outputs

<!-- markdownlint-disable MD013 -->

| Variable Name      | Description                                                |
| ------------------ | ---------------------------------------------------------- |
| build_python       | Most recent Python version supported by project           |
| matrix_json        | All Python versions supported by project as JSON string   |
| supported_versions | Space-separated list of all supported Python versions     |

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
Retrieved supported Python versions from API service 🌍
Supported versions: 3.9 3.10 3.11 3.12 3.13
Found requires-python constraint (via fallback): >=3.10
🔍 Processed requires-python constraint
Python versions from constraints: 3.10 3.11 3.12 3.13
✅ Build Python: 3.13
✅ Supported versions: 3.10 3.11 3.12 3.13
✅ Matrix JSON: {"python-version":["3.10","3.11","3.12","3.13"]}
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
- `<=X.Y` - Version X.Y and below
- `<X.Y` - Less than version X.Y
- `==X.Y` - Exact version X.Y
- `>=X.Y,<Z.W` - Range constraints (e.g., `>=3.10,<3.13`)

**Poetry constraint support:**

- `^X.Y` - Caret constraints (e.g., `^3.10` means `>=3.10,<4.0`)
- `~=X.Y` - Compatible release (e.g., `~=3.10` means `>=3.10,<3.11`)
- `==X.Y.*` - Wildcard versions (e.g., `==3.10.*` means `>=3.10,<3.11`)

### Poetry Project Support

The action also supports Poetry projects by extracting Python version constraints
from `tool.poetry.dependencies.python`:

```toml
[tool.poetry.dependencies]
python = "^3.10"     # Caret constraint: >=3.10,<4.0
python = "~=3.11"    # Compatible release: >=3.11,<3.12
python = ">=3.9,<3.13"  # Range constraint
```

Poetry constraints are automatically normalized to standard PEP 440 format
before processing.

### Fallback Method: Programming Language Classifiers

If no `requires-python` constraint exists and no Poetry configuration exists,
the action falls back to parsing explicit version classifiers:

```toml
classifiers = [
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.10",
]
```

The action supports both single and double-quoted classifier strings.

### Implementation Architecture

The action uses a single composite action implemented in `action.yaml` with
embedded bash functions for all core functionality. This provides a
self-contained, portable solution that doesn't require external dependencies.

**Core Functions:**

- `version_compare()` - Portable version comparison for major.minor versions
- `sort_versions()` - Portable version sorting (replaces non-portable sort -V)
- `fetch_python_data()` - Fetches Python version data from endoflife.date API
- `check_version_eol()` - Checks if a Python version is end-of-life
- `normalize_constraint()` - Handles Poetry caret (^) and tilde (~=) constraints
- `extract_requires_python_constraint()` - Extracts requires-python from pyproject.toml
- `extract_classifiers_fallback()` - Extracts Python versions from classifiers
- `parse_version_constraint()` - Parses and applies version constraints
- `handle_eol_versions()` - Processes EOL versions based on eol_behaviour setting
- `generate_matrix_json()` - Creates GitHub Actions matrix JSON
- `get_build_version()` - Determines latest version for builds

**Design Benefits:**

- Self-contained implementation with no external file dependencies
- Portable across all GitHub runner types (Ubuntu, macOS, Windows)
- Robust error handling and graceful degradation
- Enhanced TOML parsing supporting both single and double quotes
- Support for Poetry constraints (^3.10, ~=3.10) and complex ranges
- Dual-approach TOML parsing: Python-based primary, regex fallback
- Portable version comparison that works on all GitHub runner types

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
official sources while filtering out end-of-life (EOL) versions. This ensures
that projects use supported Python versions, improving security and
maintainability.

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

### Offline Mode Support

The action includes an `offline_mode` input for environments without internet access:

```yaml
- name: "Get Python versions (offline)"
  uses: lfreleng-actions/python-supported-versions-action@main
  with:
    offline_mode: 'true'
```

When using offline mode:

- Network requests do not occur
- Uses internal static version list: 3.9, 3.10, 3.11, 3.12, 3.13
- EOL filtering does not occur
- Perfect for air-gapped or restricted network environments

### Network Resilience

The action includes robust error handling for network-related issues:

- **Timeout Protection**: Network requests have a configurable timeout with
  retry attempts
- **Graceful Degradation**: Falls back to static versions if the API is
  unavailable
- **No Workflow Failure**: Network issues don't cause the action to fail
- **Offline Mode**: Complete network bypass when needed

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
Retrieved supported Python versions from API service 🌍
Supported versions: 3.9 3.10 3.11 3.12 3.13
```

When using offline mode:

```text
Using internal supported Python versions (offline mode) 📴
Supported versions: 3.9 3.10 3.11 3.12 3.13
```

When the endoflife.date API is unavailable:

```text
Unable to retrieve supported Python versions, using internal list ⚠️
Supported versions: 3.9 3.10 3.11 3.12 3.13
```

## Testing

### Manual Testing

To manually test the action behavior:

```bash
# Test EOL API endpoint directly
curl -s "https://endoflife.date/api/python.json" | \
  jq -r '.[] | select(.cycle | test("^3\\.(9|[1-9][0-9])$")) | .cycle'

# Test with a sample pyproject.toml
echo 'requires-python = ">=3.10"' > test_pyproject.toml

# Run the action locally (if using act or similar)
act -j test
```

### Expected Behavior

The action handles these scenarios:

- **Normal Operation**: Fetches current Python versions, applies constraints
- **Network Issues**: Falls back to internal version list with warnings
- **Offline Mode**: Uses internal list, skips all network calls
- **EOL Versions**: Handles according to eol_behaviour setting
- **Invalid Constraints**: Provides clear error messages

### EOL Status Reference

Current Python EOL schedule (as of 2025):

- **Python 3.8**: EOL October 7, 2024 (excluded by default)
- **Python 3.9**: EOL October 31, 2025 (included)
- **Python 3.10**: EOL October 31, 2026 (included)
- **Python 3.11**: EOL October 31, 2027 (included)
- **Python 3.12**: EOL October 31, 2028 (included)
- **Python 3.13**: EOL October 31, 2029 (included)

The action automatically updates this information by fetching current EOL data
from endoflife.date, ensuring accuracy without manual intervention.

**Note:** The `eol_behaviour` input controls how the action handles EOL versions:

- `warn`: Include EOL versions with warnings
- `strip`: Exclude EOL versions with warnings
- `fail`: Action exits with error when detecting EOL versions
