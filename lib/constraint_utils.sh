#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Shared constraint parsing utilities used by tests and action logic.
# This library intentionally avoids external tool dependencies beyond
# standard POSIX utilities (grep, sed, awk) to keep tests portable.

# Trim leading/trailing whitespace
_trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Version comparison for X.Y versions only
# Usage: version_compare "3.10" op "3.11"
# Ops: lt, le, gt, ge, eq
version_compare() {
  local v1="$1" op="$2" v2="$3"
  local v1_major="${v1%%.*}" v1_minor="${v1##*.}"
  local v2_major="${v2%%.*}" v2_minor="${v2##*.}"
  v1_major=$((v1_major)) || return 1
  v1_minor=$((v1_minor)) || return 1
  v2_major=$((v2_major)) || return 1
  v2_minor=$((v2_minor)) || return 1

  case "$op" in
    lt) [[ $v1_major -lt $v2_major ]] || [[ $v1_major -eq $v2_major && $v1_minor -lt $v2_minor ]] ;;
    le) [[ $v1_major -lt $v2_major ]] || [[ $v1_major -eq $v2_major && $v1_minor -le $v2_minor ]] ;;
    gt) [[ $v1_major -gt $v2_major ]] || [[ $v1_major -eq $v2_major && $v1_minor -gt $v2_minor ]] ;;
    ge) [[ $v1_major -gt $v2_major ]] || [[ $v1_major -eq $v2_major && $v1_minor -ge $v2_minor ]] ;;
    eq) [[ $v1_major -eq $v2_major && $v1_minor -eq $v2_minor ]] ;;
    *) return 1 ;;
  esac
}

# Sort a space-separated list of X.Y versions ascending
sort_versions() {
  local versions="$1"
  printf '%s\n' "$versions" | tr ' ' '\n' | grep -v '^$' | sort -t. -k1,1n -k2,2n | tr '\n' ' ' | sed 's/ $//'
}

# Normalize a single constraint token (does not fully parse expressions)
# Supports:
# - ^X.Y or ^X.Y.Z => >=X.Y,<X+1.0
# - ~=X.Y or ~=X.Y.Z => >=X.Y,<X.(Y+1)
# - ==X.Y.* => >=X.Y,<X.(Y+1)
# - Strips patch segments from <,<=,>,>= bounds (e.g., <3.13.2 -> <3.13)
# Leaves "!=..." untouched for the parser to handle.
normalize_constraint() {
  local c="$1"

  # Exclusions are forwarded unchanged
  if [[ "$c" == \!* ]]; then
    echo "$c"
    return 0
  fi

  # ^X.Y.Z
  if [[ "$c" =~ ^\^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}"
    local next_major=$((maj+1))
    echo ">=${maj}.${min},<${next_major}.0"
    return 0
  fi
  # ^X.Y
  if [[ "$c" =~ ^\^([0-9]+)\.([0-9]+)$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}"
    local next_major=$((maj+1))
    echo ">=${maj}.${min},<${next_major}.0"
    return 0
  fi
  # ~=X.Y.Z
  if [[ "$c" =~ ^~=([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}"
    local next_min=$((min+1))
    echo ">=${maj}.${min},<${maj}.${next_min}"
    return 0
  fi
  # ~=X.Y
  if [[ "$c" =~ ^~=([0-9]+)\.([0-9]+)$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}"
    local next_min=$((min+1))
    echo ">=${maj}.${min},<${maj}.${next_min}"
    return 0
  fi
  # ==X.Y.*
  if [[ "$c" =~ ^==([0-9]+)\.([0-9]+)\.\*$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}"
    local next_min=$((min+1))
    echo ">=${maj}.${min},<${maj}.${next_min}"
    return 0
  fi

  # Strip patch for comparative operators (<,<=,>,>=) e.g. <3.13.5 -> <3.13
  # shellcheck disable=SC2001
  c=$(echo "$c" | sed 's/\([<>=]\+\)\([0-9]\+\.[0-9]\+\)\.[0-9]\+/\1\2/g')

  echo "$c"
}

# Parse a requires-python constraint into a space-separated list of versions
# available in $2. Returns 0 with list on stdout or 1 on failure/no matches.
parse_version_constraint() {
  local constraint="$1"
  local all_versions="$2"
  local result=''

  constraint=$(normalize_constraint "$constraint")

  if [[ "$constraint" == *","* ]]; then
    # Intersection of parts
    local candidates="$all_versions"
    local IFS=','; local parts; read -ra parts <<< "$constraint"; unset IFS
    local part
    for part in "${parts[@]}"; do
      part=$(echo "$part" | _trim)
      local temp=''

      case "$part" in
        \>=*)
          local min="${part#>=}"
          for v in $candidates; do version_compare "$v" ge "$min" && temp="$temp $v"; done
          ;;
        \>*)
          local min="${part#>}"
          for v in $candidates; do version_compare "$v" gt "$min" && temp="$temp $v"; done
          ;;
        \<=*)
          local max="${part#<=}"
          for v in $candidates; do version_compare "$v" le "$max" && temp="$temp $v"; done
          ;;
        \<*)
          local max="${part#<}"
          for v in $candidates; do version_compare "$v" lt "$max" && temp="$temp $v"; done
          ;;
        ==*)
          local eq="${part#==}"
          for v in $candidates; do if version_compare "$v" eq "$eq"; then temp="$v"; break; fi; done
          ;;
        !=*)
          local ex_raw="${part#!=}"
          local ex="$ex_raw"
          if [[ "$ex_raw" =~ ^([0-9]+)\.([0-9]+) ]]; then
            ex="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
          fi
          for v in $candidates; do if ! version_compare "$v" eq "$ex"; then temp="$temp $v"; fi; done
          ;;
        *)
          return 1
          ;;
      esac

      if [[ -z "$temp" ]]; then
        candidates=""
        break
      fi
      # Deduplicate and trim
      candidates=$(echo "$temp" | tr ' ' '\n' | grep -v '^$' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ $//')
    done
    result="$candidates"
  else
    case "$constraint" in
      \>=*)
        local min="${constraint#>=}"
        for v in $all_versions; do version_compare "$v" ge "$min" && result="$result $v"; done
        ;;
      \>*)
        local min="${constraint#>}"
        for v in $all_versions; do version_compare "$v" gt "$min" && result="$result $v"; done
        ;;
      \<=*)
        local max="${constraint#<=}"
        for v in $all_versions; do version_compare "$v" le "$max" && result="$result $v"; done
        ;;
      \<*)
        local max="${constraint#<}"
        for v in $all_versions; do version_compare "$v" lt "$max" && result="$result $v"; done
        ;;
      ==*)
        local eq="${constraint#==}"
        for v in $all_versions; do if version_compare "$v" eq "$eq"; then result="$v"; break; fi; done
        ;;
      !=*)
        local ex_raw="${constraint#!=}"
        local ex="$ex_raw"
        if [[ "$ex_raw" =~ ^([0-9]+)\.([0-9]+) ]]; then
          ex="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        fi
        for v in $all_versions; do if ! version_compare "$v" eq "$ex"; then result="$result $v"; fi; done
        ;;
      *)
        return 1
        ;;
    esac
  fi

  result=$(echo "$result" | _trim)
  if [[ -z "$result" ]]; then
    return 1
  fi

  sort_versions "$result"
  return 0
}

# Extract requires-python constraint from a setup.cfg file.
# Returns 0 with the constraint on stdout, or 1 if absent / file missing.
#
# Looks at [options] python_requires = <constraint>. The PEP 517/518
# declarative setuptools format does not quote the value, so we do not
# strip quotes here (configparser-level helper below handles both).
extract_requires_python_setup_cfg() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  # Prefer Python's configparser if Python 3 is available — INI parsing
  # rules (continuation lines, comment markers, case-insensitive keys)
  # are non-trivial and easy to get wrong with grep/sed.
  if command -v python3 >/dev/null 2>&1; then
    local val
    val=$(python3 - "$file" <<'PY' 2>/dev/null
import configparser, sys
cfg = configparser.ConfigParser()
try:
    cfg.read(sys.argv[1])
except configparser.Error:
    sys.exit(1)
val = cfg.get("options", "python_requires", fallback=None)
if val is None:
    sys.exit(1)
val = val.strip().strip("'\"")
if not val:
    sys.exit(1)
print(val)
PY
) || val=""
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi

  # Fallback: awk-based extraction. Limited to single-line values and
  # the canonical key name; sufficient for the overwhelming majority
  # of real-world setup.cfg files.
  local constraint
  constraint=$(awk '
    BEGIN { insec = 0 }
    /^[[:space:]]*[#;]/ { next }
    /^\[/ {
      insec = ($0 ~ /^\[options\][[:space:]]*$/) ? 1 : 0
      next
    }
    insec && /^[[:space:]]*python_requires[[:space:]]*=/ {
      sub(/^[[:space:]]*python_requires[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      gsub(/^["\x27]|["\x27]$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null)

  if [[ -n "$constraint" ]]; then
    echo "$constraint"
    return 0
  fi
  return 1
}

# Extract Python versions from Programming Language classifiers in setup.cfg.
# Supports both the modern setuptools key (`classifiers`) and the legacy
# PBR/distutils key (`classifier`) under [metadata]. Classifier values in
# setup.cfg are typically multi-line indented blocks.
# Prints space-separated versions in first-seen order; returns 0 on success.
extract_classifiers_setup_cfg() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  if command -v python3 >/dev/null 2>&1; then
    local versions
    versions=$(python3 - "$file" <<'PY' 2>/dev/null
import configparser, re, sys
cfg = configparser.ConfigParser()
try:
    cfg.read(sys.argv[1])
except configparser.Error:
    sys.exit(1)
# Modern setuptools uses 'classifiers'; PBR and legacy distutils use
# the singular 'classifier'. Some files include both; merge them.
raw = []
for key in ("classifiers", "classifier"):
    val = cfg.get("metadata", key, fallback=None)
    if val:
        raw.append(val)
if not raw:
    sys.exit(1)
seen = []
for block in raw:
    for line in block.splitlines():
        m = re.search(r"Programming Language :: Python :: (\d+\.\d+)(?![.\d])", line)
        if m and m.group(1) not in seen:
            seen.append(m.group(1))
if not seen:
    sys.exit(1)
print(" ".join(seen))
PY
) || versions=""
    if [[ -n "$versions" ]]; then
      echo "$versions"
      return 0
    fi
  fi

  # Fallback: a simpler grep over the raw file. Continuation lines for
  # classifier values in setup.cfg start with whitespace, so grepping
  # for the well-known classifier pattern catches them regardless of
  # section structure. This is intentionally permissive — the Python
  # path above is preferred.
  local lines versions
  lines=$(grep -v '^[[:space:]]*[#;]' "$file" 2>/dev/null | \
          grep -E 'Programming Language :: Python :: [0-9]+\.[0-9]+') || true
  if [[ -z "$lines" ]]; then
    return 1
  fi
  versions=$(echo "$lines" | grep -oE 'Python :: [0-9]+\.[0-9]+' | \
             grep -oE '[0-9]+\.[0-9]+' | awk '!seen[$0]++' | \
             tr '\n' ' ' | sed 's/ $//')
  if [[ -n "$versions" ]]; then
    echo "$versions"
    return 0
  fi
  return 1
}

# Extract requires-python constraint from a TOML file (best-effort, grep-based)
# Prints the constraint and returns 0 on success; returns 1 on failure/not found.
extract_requires_python_constraint() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  # Ignore commented lines, match first requires-python occurrence
  local c
  c=$(grep -v '^[[:space:]]*#' "$file" 2>/dev/null | \
      grep -E 'requires-python[[:space:]]*=' | \
      sed -E 's/.*requires-python[[:space:]]*=[[:space:]]*['"'"'"]([^'"'"'"]*)['"'"'"].*/\1/' | \
      head -1)

  if [[ -n "$c" ]]; then
    echo "$c"
    return 0
  fi

  # Fallback: Poetry [tool.poetry.dependencies] python constraint
  c=$(awk '
    BEGIN{insec=0}
    /^\[tool\.poetry\.dependencies\]/{insec=1; next}
    /^\[.*\]/{if(insec) exit}
    insec{print}
  ' "$file" 2>/dev/null | \
      grep -v '^[[:space:]]*#' | \
      grep -E '^[[:space:]]*python[[:space:]]*=' | \
      sed -E 's/.*=[[:space:]]*['"'"'"]([^'"'"'"]*)['"'"'"].*/\1/' | \
      head -1)

  if [[ -n "$c" ]]; then
    echo "$c"
    return 0
  fi

  return 1
}

# Extract Python versions from Programming Language classifiers in a TOML file
# Prints space-separated versions in first-seen order. Returns 0 on success, 1 if none found or file missing.
extract_classifiers_fallback() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  # Find classifier lines and extract X.Y while preserving order and deduplicating
  local lines versions
  lines=$(grep -v '^[[:space:]]*#' "$file" 2>/dev/null | grep -E 'Programming Language :: Python :: [0-9]+\.[0-9]+') || true
  if [[ -z "$lines" ]]; then
    return 1
  fi
  versions=$(echo "$lines" | grep -oE '[0-9]+\.[0-9]+' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ $//')
  if [[ -n "$versions" ]]; then
    echo "$versions"
    return 0
  fi
  return 1
}

# Generate matrix JSON string from space-separated versions.
# Expected formatting: '{"python-version": ["3.9","3.10"]}' or empty array with a space after colon.
generate_matrix_json() {
  local versions="$1"
  versions=$(echo "$versions" | _trim)
  if [[ -z "$versions" ]]; then
    echo '{"python-version": []}'
    return 0
  fi
  local arr="" v
  for v in $versions; do
    if [[ -z "$arr" ]]; then
      arr="\"$v\""
    else
      arr="$arr,\"$v\""
    fi
  done
  echo "{\"python-version\": [$arr]}"
}

# Validate version format: ensures all tokens are X.Y numeric pairs.
validate_version_format() {
  local versions="$1" v
  for v in $versions; do
    [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
  done
  return 0
}

# Validate JSON format for our expected shape:
# - Must contain exactly the "python-version" key
# - Must have an array value (content not strictly validated)
validate_json_format() {
  local json="$1"
  # Basic brace check and key presence
  if [[ "$json" =~ ^\{[[:space:]]*\"python-version\"[[:space:]]*:[[:space:]]*\[[^]]*\][[:space:]]*\}$ ]]; then
    return 0
  fi
  return 1
}

# Select the latest version (highest) from a space-separated list.
get_build_version() {
  local versions="$1"
  versions=$(echo "$versions" | _trim)
  [[ -n "$versions" ]] || return 1
  local sorted
  sorted=$(sort_versions "$versions")
  echo "$sorted" | tr ' ' '\n' | tail -1
}

# High-level function:
# - Try requires-python constraint; parse against available versions
# - Else fallback to classifiers, filter against available versions
# - Returns 0 printing space-separated versions or 1 if none found
process_python_constraints() {
  local file="$1"
  local available="$2"

  [[ -f "$file" ]] || return 1
  [[ -n "$available" ]] || return 1

  local constraint versions classifiers out=""
  if constraint=$(extract_requires_python_constraint "$file"); then
    if versions=$(parse_version_constraint "$constraint" "$available"); then
      echo "$versions"
      return 0
    fi
  fi

  if classifiers=$(extract_classifiers_fallback "$file"); then
    # Filter to those present in available
    local v
    for v in $classifiers; do
      for a in $available; do
        if [[ "$v" == "$a" ]]; then
          out="$out $v"
          break
        fi
      done
    done
    out=$(echo "$out" | _trim)
    if [[ -n "$out" ]]; then
      # Ensure ascending order per available list ordering
      # Using sort_versions keeps numeric sort consistent
      sort_versions "$out"
      return 0
    fi
  fi

  return 1
}

# High-level function for setup.cfg sources. Mirrors process_python_constraints
# but reads python_requires from [options] and classifiers from [metadata].
# Returns 0 printing space-separated versions, or 1 if none determinable.
process_python_constraints_setup_cfg() {
  local file="$1"
  local available="$2"

  [[ -f "$file" ]] || return 1
  [[ -n "$available" ]] || return 1

  local constraint versions classifiers out=""
  if constraint=$(extract_requires_python_setup_cfg "$file"); then
    if versions=$(parse_version_constraint "$constraint" "$available"); then
      echo "$versions"
      return 0
    fi
  fi

  if classifiers=$(extract_classifiers_setup_cfg "$file"); then
    local v a
    for v in $classifiers; do
      for a in $available; do
        if [[ "$v" == "$a" ]]; then
          out="$out $v"
          break
        fi
      done
    done
    out=$(echo "$out" | _trim)
    if [[ -n "$out" ]]; then
      sort_versions "$out"
      return 0
    fi
  fi

  return 1
}

# Determine which metadata file to use for extraction.
# Precedence:
#   1. pyproject.toml — if it yields a usable result
#   2. setup.cfg — fallback for legacy setuptools/PBR projects
# Prints the absolute or relative path on stdout (caller uses it) and
# echoes a short tag on file descriptor 3 (or stderr if 3 is closed)
# indicating which source was selected: 'pyproject', 'setup.cfg', or
# 'none'. Returns 0 if at least one of the candidate files exists, or
# 1 if neither is present.
detect_metadata_source() {
  local path_prefix="$1"
  local py="${path_prefix%/}/pyproject.toml"
  local cfg="${path_prefix%/}/setup.cfg"
  if [[ -f "$py" ]]; then
    echo "$py"
    printf 'pyproject\n' 1>&2
    return 0
  fi
  if [[ -f "$cfg" ]]; then
    echo "$cfg"
    printf 'setup.cfg\n' 1>&2
    return 0
  fi
  printf 'none\n' 1>&2
  return 1
}
