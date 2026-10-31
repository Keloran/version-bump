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

test_updates_android_release() {
  local temp_dir output version count_line files_line
  temp_dir="$(mktemp -d)"
  mkdir -p "${temp_dir}/app"
  cat > "${temp_dir}/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.7.0" apply false
}
EOF
  cat > "${temp_dir}/app/build.gradle.kts" <<'EOF'
android {
    defaultConfig {
        versionCode = 42
        versionName = "0.1.0" // release version
    }
    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = "secret"
            keyAlias = "release"
            keyPassword = "secret"
        }
    }
}
EOF
  cat > "${temp_dir}/expected" <<'EOF'
android {
    defaultConfig {
        versionCode = 42
        versionName = "2.3.4-rc.1+build.5" // release version
    }
    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = "secret"
            keyAlias = "release"
            keyPassword = "secret"
        }
    }
}
EOF
  cp "${temp_dir}/build.gradle.kts" "${temp_dir}/expected-root"
  version="$(env -u GITHUB_OUTPUT INPUT_VERSION= GITHUB_RELEASE_TAG=v2.3.4-rc.1+build.5 bash "${ROOT_DIR}/scripts/extract-version.sh" | sed -n 's/^version=//p')"
  output="$(run_update "${temp_dir}" VERSION="${version}" SEARCH_SUBDIRS=true)"
  count_line="$(printf '%s\n' "${output}" | sed -n 's/^files-count=//p')"
  files_line="$(printf '%s\n' "${output}" | sed -n 's/^updated-files=//p')"
  assert_eq "${count_line}" "1" "only the Android module should be counted"
  assert_eq "${files_line}" "./app/build.gradle.kts" "root plugin configuration should not be reported as updated"
  diff -u "${temp_dir}/expected" "${temp_dir}/app/build.gradle.kts"
  diff -u "${temp_dir}/expected-root" "${temp_dir}/build.gradle.kts"
  rm -rf "${temp_dir}"
}

test_gradle_literal_syntax_and_unrelated_values() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  cat > "${temp_dir}/build.gradle" <<'EOF'
version = "0.1.0"
version='0.1.0'
version '0.1.0'
version "0.1.0"
    versionName "0.1.0"
    versionName '0.1.0'
    versionName = "0.1.0"; // keep comment
	versionName='0.1.0'
// versionName = "comment"
// version = "comment"
def version = "local variable"
versionName = project.version.toString()
versionName = "${major}.${minor}"
versionName = "prefix" + suffix
versionNameSuffix = "-debug"
versionCode 42
ext.version = "unrelated property"
dependencyVersion = "1.0.0"
EOF
  cat > "${temp_dir}/expected" <<'EOF'
version = "1.2.3"
version='1.2.3'
version '1.2.3'
version "1.2.3"
    versionName "1.2.3"
    versionName '1.2.3'
    versionName = "1.2.3"; // keep comment
	versionName='1.2.3'
// versionName = "comment"
// version = "comment"
def version = "local variable"
versionName = project.version.toString()
versionName = "${major}.${minor}"
versionName = "prefix" + suffix
versionNameSuffix = "-debug"
versionCode 42
ext.version = "unrelated property"
dependencyVersion = "1.0.0"
EOF
  output="$(run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=false)"
  assert_file_contains "${temp_dir}/build.gradle" 'versionName "1.2.3"' "Groovy Android version should update"
  diff -u "${temp_dir}/expected" "${temp_dir}/build.gradle"
  assert_eq "$(printf '%s\n' "${output}" | sed -n 's/^files-count=//p')" "1" "multiple declarations should count as one file"

  output="$(run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=false)"
  assert_eq "$(printf '%s\n' "${output}" | sed -n 's/^files-count=//p')" "0" "repeated bumps should report no changes"
  diff -u "${temp_dir}/expected" "${temp_dir}/build.gradle"
  rm -rf "${temp_dir}"
}

test_gradle_without_literal_version_fails() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  cat > "${temp_dir}/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.7.0"
}
versionName = project.version.toString()
EOF
  cp "${temp_dir}/build.gradle.kts" "${temp_dir}/expected"
  if output="$(run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=false 2>&1)"; then
    echo "Expected failure for Gradle files without a supported version declaration" >&2
    exit 1
  fi
  assert_eq "$(printf '%s\n' "${output}" | sed -n 's/^files-count=//p')" "0" "unmatched Gradle files should not count as updated"
  diff -u "${temp_dir}/expected" "${temp_dir}/build.gradle.kts"
  rm -rf "${temp_dir}"
}

test_android_search_subdirs_false() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  mkdir -p "${temp_dir}/app"
  printf 'version = "0.1.0"\n' > "${temp_dir}/build.gradle.kts"
  printf 'versionName = "0.1.0"\n' > "${temp_dir}/app/build.gradle.kts"
  output="$(run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=false)"
  assert_eq "$(printf '%s\n' "${output}" | sed -n 's/^files-count=//p')" "1" "only the root Gradle file should update"
  assert_file_contains "${temp_dir}/build.gradle.kts" 'version = "1.2.3"' "root Gradle version should update"
  assert_file_contains "${temp_dir}/app/build.gradle.kts" 'versionName = "0.1.0"' "nested Android version should stay unchanged"
  rm -rf "${temp_dir}"
}

test_gradle_kts_stays_valid_kotlin() {
  local temp_dir
  temp_dir=$(mktemp -d)
  cat > "${temp_dir}/build.gradle.kts" <<'EOF'
plugins {
    id("org.example.plugin") version "9.9.9"
}
project.version = "0.1.0"
android {
    defaultConfig {
        versionName = project.version.toString()
    }
}
EOF

  run_update "${temp_dir}" VERSION=1.2.3 SEARCH_SUBDIRS=false >/dev/null
  assert_file_contains "${temp_dir}/build.gradle.kts" 'project.version = "1.2.3"' "project.version should update, with double quotes, as single aren't valid Kotlin"
  assert_file_contains "${temp_dir}/build.gradle.kts" 'id("org.example.plugin") version "9.9.9"' "a plugin's version should not change"
  assert_file_contains "${temp_dir}/build.gradle.kts" 'versionName = project.version.toString()' "a computed versionName should not change"

  rm -rf "${temp_dir}"
}

test_updates_root_and_subdirectory_once
test_search_subdirs_false_skips_nested_files
test_updates_project_pyproject_section
test_updates_android_release
test_gradle_literal_syntax_and_unrelated_values
test_gradle_without_literal_version_fails
test_android_search_subdirs_false
test_gradle_kts_stays_valid_kotlin

echo "update-version-files tests passed"
