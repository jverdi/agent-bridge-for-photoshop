#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"

if [[ ! -d "${DOCS_DIR}" ]]; then
  echo "Docs directory not found: ${DOCS_DIR}" >&2
  exit 1
fi

mint_bin="$(command -v mint || true)"

run_mint() {
  if [[ -n "${mint_bin}" ]]; then
    # Mint CLI is more stable on Node 22 than newer runtimes.
    npx -y node@22 "${mint_bin}" "$@"
    return
  fi

  # CI fallback (expects Node 22 from actions/setup-node).
  npx -y mint "$@"
}

cd "${DOCS_DIR}"
run_mint validate
run_mint broken-links
