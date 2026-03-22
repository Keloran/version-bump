#!/usr/bin/env bash
set -euo pipefail

semver_pattern='^[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

emit_output() {
  local key=$1
  local value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  else
    echo "${key}=${value}"
  fi
}

main() {
  local version=""

  if [[ -n "${INPUT_VERSION:-}" ]]; then
    version="${INPUT_VERSION}"
    echo "Using provided version: ${version}"
  elif [[ -n "${GITHUB_RELEASE_TAG:-}" ]]; then
    version="${GITHUB_RELEASE_TAG}"
    echo "Extracted version from release tag: ${version}"
  elif [[ "${GITHUB_CONTEXT_REF:-}" =~ ^refs/tags/ ]]; then
    version="${GITHUB_CONTEXT_REF#refs/tags/}"
    echo "Extracted version from ref tag: ${version}"
  elif [[ "${GITHUB_CONTEXT_REF:-}" =~ ^refs/heads/ ]]; then
    if git describe --tags --abbrev=0 >/dev/null 2>&1; then
      version="$(git describe --tags --abbrev=0)"
      echo "Using latest tag: ${version}"
    else
      echo "No version provided and no tags found" >&2
      exit 1
    fi
  elif [[ -n "${GITHUB_CONTEXT_REF_NAME:-}" ]]; then
    version="${GITHUB_CONTEXT_REF_NAME}"
    echo "Extracted version from ref name: ${version}"
  else
    echo "Unable to determine version from GitHub context" >&2
    echo "github.ref='${GITHUB_CONTEXT_REF:-}'" >&2
    echo "github.ref_name='${GITHUB_CONTEXT_REF_NAME:-}'" >&2
    echo "github.event.release.tag_name='${GITHUB_RELEASE_TAG:-}'" >&2
    exit 1
  fi

  version="${version#v}"

  if [[ ! "${version}" =~ ${semver_pattern} ]]; then
    echo "Invalid version format: ${version}" >&2
    echo "Expected format: X.Y.Z, X.Y, or X (with optional pre-release/build suffixes)" >&2
    exit 1
  fi

  emit_output "version" "${version}"
  echo "Final version: ${version}"
}

main "$@"
