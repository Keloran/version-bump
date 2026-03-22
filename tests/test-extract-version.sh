#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/extract-version.sh"

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

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "Assertion failed: ${message}" >&2
    echo "Expected to find: ${needle}" >&2
    echo "In: ${haystack}" >&2
    exit 1
  fi
}

run_script() {
  env "$@" bash "${SCRIPT}" 2>&1
}

run_script_expect_failure() {
  set +e
  local output
  output="$(env "$@" bash "${SCRIPT}" 2>&1)"
  local status=$?
  set -e
  if [[ ${status} -eq 0 ]]; then
    echo "Expected failure but command succeeded" >&2
    echo "${output}" >&2
    exit 1
  fi
  printf '%s' "${output}"
}

test_explicit_input_version() {
  local output
  output="$(run_script INPUT_VERSION=v1.2.3)"
  assert_contains "${output}" "version=1.2.3" "explicit input should be normalized"
}

test_release_tag_fallback() {
  local output
  output="$(run_script GITHUB_RELEASE_TAG=v2.3.4-rc.1)"
  assert_contains "${output}" "version=2.3.4-rc.1" "release tag should be used when present"
}

test_ref_tag_fallback() {
  local output
  output="$(run_script GITHUB_CONTEXT_REF=refs/tags/v3.4.5)"
  assert_contains "${output}" "version=3.4.5" "ref tag should be parsed"
}

test_branch_uses_latest_git_tag() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  git -C "${temp_dir}" init >/dev/null
  git -C "${temp_dir}" config user.email test@example.com
  git -C "${temp_dir}" config user.name tester
  echo "hello" > "${temp_dir}/README.md"
  git -C "${temp_dir}" add README.md
  git -C "${temp_dir}" commit -m init >/dev/null
  git -C "${temp_dir}" tag v4.5.6

  output="$(cd "${temp_dir}" && run_script GITHUB_CONTEXT_REF=refs/heads/main)"
  rm -rf "${temp_dir}"

  assert_contains "${output}" "version=4.5.6" "branch fallback should use latest git tag"
}

test_ref_name_fallback() {
  local output
  output="$(run_script GITHUB_CONTEXT_REF_NAME=v5.6.7)"
  assert_contains "${output}" "version=5.6.7" "ref name should be used when ref is unavailable"
}

test_invalid_version_rejected() {
  local output
  output="$(run_script_expect_failure INPUT_VERSION=v.1.2.3)"
  assert_contains "${output}" "Invalid version format" "invalid semver should fail"
}

test_missing_context_rejected() {
  local output
  output="$(run_script_expect_failure)"
  assert_contains "${output}" "Unable to determine version from GitHub context" "missing context should fail"
}

test_explicit_input_version
test_release_tag_fallback
test_ref_tag_fallback
test_branch_uses_latest_git_tag
test_ref_name_fallback
test_invalid_version_rejected
test_missing_context_rejected

echo "extract-version tests passed"
