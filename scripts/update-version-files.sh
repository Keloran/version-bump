#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${VERSION:-}" ]]; then
  echo "VERSION must be set" >&2
  exit 1
fi

SEARCH_SUBDIRS="${SEARCH_SUBDIRS:-true}"
UPDATED_FILES=()
declare -A SEEN_FILES=()

emit_output() {
  local key=$1
  local value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  else
    echo "${key}=${value}"
  fi
}

record_updated() {
  local file=$1
  if [[ -z "${SEEN_FILES[$file]:-}" ]]; then
    UPDATED_FILES+=("${file}")
    SEEN_FILES["$file"]=1
  fi
}

update_json_version() {
  local file=$1
  local tmp_file
  if [[ -f "${file}" ]]; then
    echo "Updating ${file}"
    tmp_file="$(mktemp)"
    if jq --arg version "${VERSION}" '.version = $version' "${file}" > "${tmp_file}" && mv "${tmp_file}" "${file}"; then
      record_updated "${file}"
      echo "Updated ${file}"
      return 0
    fi
    rm -f "${tmp_file}"
    echo "Failed to update ${file}" >&2
    return 1
  fi
  return 1
}

update_toml_version() {
  local file=$1
  local section=${2:-}
  if [[ -f "${file}" ]]; then
    echo "Updating ${file}"
    if [[ -n "${section}" ]]; then
      if ! grep -q "^\[${section}\]" "${file}"; then
        return 1
      fi
      sed -i "/^\[${section}\]/,/^\[.*\]/{s/^version = \".*\"/version = \"${VERSION}\"/}" "${file}"
    else
      sed -i "0,/^version = \".*\"/{s/^version = \".*\"/version = \"${VERSION}\"/}" "${file}"
    fi
    record_updated "${file}"
    echo "Updated ${file}"
    return 0
  fi
  return 1
}

update_setup_py() {
  local file=$1
  if [[ -f "${file}" ]]; then
    echo "Updating ${file}"
    sed -i "s/version=['\"][^'\"]*['\"]/version='${VERSION}'/" "${file}"
    record_updated "${file}"
    echo "Updated ${file}"
    return 0
  fi
  return 1
}

update_gradle_version() {
  local file=$1
  if [[ -f "${file}" ]]; then
    echo "Updating ${file}"
    sed -i "s/version = \".*\"/version = \"${VERSION}\"/" "${file}"
    sed -i "s/version=\".*\"/version=\"${VERSION}\"/" "${file}"
    sed -i "s/version = ['\"][^'\"]*['\"]/version = '${VERSION}'/" "${file}"
    sed -i "s/version '[^']*'/version '${VERSION}'/" "${file}"
    sed -i "s/version \"[^\"]*\"/version \"${VERSION}\"/" "${file}"
    record_updated "${file}"
    echo "Updated ${file}"
    return 0
  fi
  return 1
}

echo "Updating version to: ${VERSION}"

update_json_version "package.json" || true
update_toml_version "Cargo.toml" "package" || true
update_setup_py "setup.py" || true
update_toml_version "pyproject.toml" "tool.poetry" || update_toml_version "pyproject.toml" "project" || true
update_gradle_version "build.gradle" || true
update_gradle_version "build.gradle.kts" || true

if [[ "${SEARCH_SUBDIRS}" == "true" ]]; then
  echo "Searching subdirectories"

  while IFS= read -r -d '' file; do
    update_json_version "${file}" || true
  done < <(find . -mindepth 2 -name "package.json" -not -path "./node_modules/*" -not -path "./.git/*" -print0)

  while IFS= read -r -d '' file; do
    update_toml_version "${file}" "package" || true
  done < <(find . -mindepth 2 -name "Cargo.toml" -not -path "./.git/*" -print0)

  while IFS= read -r -d '' file; do
    update_toml_version "${file}" "tool.poetry" || update_toml_version "${file}" "project" || true
  done < <(find . -mindepth 2 -name "pyproject.toml" -not -path "./.git/*" -print0)

  while IFS= read -r -d '' file; do
    update_setup_py "${file}" || true
  done < <(find . -mindepth 2 -name "setup.py" -not -path "./.git/*" -print0)

  while IFS= read -r -d '' file; do
    update_gradle_version "${file}" || true
  done < <(find . -mindepth 2 \( -name "build.gradle" -o -name "build.gradle.kts" \) -not -path "./.git/*" -print0)
fi

files_count=${#UPDATED_FILES[@]}
if [[ ${files_count} -gt 0 ]]; then
  updated_files_str=$(printf '%s,' "${UPDATED_FILES[@]}")
  updated_files_str=${updated_files_str%,}
  emit_output "updated-files" "${updated_files_str}"
  emit_output "files-count" "${files_count}"
  printf 'Successfully updated %s file(s)\n' "${files_count}"
  printf '  - %s\n' "${UPDATED_FILES[@]}"
else
  emit_output "updated-files" ""
  emit_output "files-count" "0"
  echo "No version files found to update" >&2
  exit 1
fi
