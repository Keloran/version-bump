#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT_DIR}/tests/test-extract-version.sh"
bash "${ROOT_DIR}/tests/test-update-version-files.sh"

echo "all tests passed"
