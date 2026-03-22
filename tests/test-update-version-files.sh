#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/update-version-files.sh"

assert_eq() {
  local actual=$1
  local expected=$2
  local message=$3
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Assertion failed: ${message}" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file=$1
  local needle=$2
  local message=$3
  if ! grep -Fq "${needle}" "${file}"; then
    echo "Assertion failed: ${message}" >&2
    echo "Expected to find: ${needle}" >&2
    echo "In file: ${file}" >&2
    exit 1
  fi
}

run_update() {
  local temp_dir=$1
  shift
  (cd "${temp_dir}" && env -u GITHUB_OUTPUT "$@" bash "${SCRIPT}")
}

test_updates_root_and_subdirectory_once() {
  local temp_dir output count_line files_line
  temp_dir="$(mktemp -d)"

  cat > "${temp_dir}/package.json" <<'EOF'
{"name":"demo","version":"0.1.0"}
EOF

  mkdir -p "${temp_dir}/nested"
  cat > "${temp_dir}/nested/package.json" <<'EOF'
{"name":"nested","version":"0.2.0"}
EOF

  output="$(run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=true)"
  count_line="$(printf '%s\n' "${output}" | awk -F= '/^files-count=/{print $2}' | tail -n1)"
  files_line="$(printf '%s\n' "${output}" | awk -F= '/^updated-files=/{print $2}' | tail -n1)"

  assert_eq "${count_line}" "2" "root and nested package files should be counted once each"
  assert_eq "${files_line}" "package.json,./nested/package.json" "updated files should not contain duplicates"
  assert_file_contains "${temp_dir}/package.json" '"version": "1.2.3"' "root package version should update"
  assert_file_contains "${temp_dir}/nested/package.json" '"version": "1.2.3"' "nested package version should update"

  rm -rf "${temp_dir}"
}

test_search_subdirs_false_skips_nested_files() {
  local temp_dir output count_line
  temp_dir="$(mktemp -d)"

  cat > "${temp_dir}/package.json" <<'EOF'
{"name":"demo","version":"0.1.0"}
EOF

  mkdir -p "${temp_dir}/nested"
  cat > "${temp_dir}/nested/package.json" <<'EOF'
{"name":"nested","version":"0.2.0"}
EOF

  output="$(run_update "${temp_dir}" VERSION=2.0.0 SEARCH_SUBDIRS=false)"
  count_line="$(printf '%s\n' "${output}" | awk -F= '/^files-count=/{print $2}' | tail -n1)"

  assert_eq "${count_line}" "1" "only root package should update when subdirectory search is disabled"
  assert_file_contains "${temp_dir}/package.json" '"version": "2.0.0"' "root package version should update"
  assert_file_contains "${temp_dir}/nested/package.json" '"version":"0.2.0"' "nested package should remain unchanged"

  rm -rf "${temp_dir}"
}

test_updates_project_pyproject_section() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  cat > "${temp_dir}/pyproject.toml" <<'EOF'
[project]
name = "demo"
version = "0.3.0"
EOF

  run_update "${temp_dir}" VERSION=3.4.5 SEARCH_SUBDIRS=false >/dev/null
  assert_file_contains "${temp_dir}/pyproject.toml" 'version = "3.4.5"' "project version should update"

  rm -rf "${temp_dir}"
}

test_updates_root_and_subdirectory_once
test_search_subdirs_false_skips_nested_files
test_updates_project_pyproject_section

echo "update-version-files tests passed"
