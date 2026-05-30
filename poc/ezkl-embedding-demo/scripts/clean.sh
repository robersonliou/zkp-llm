#!/usr/bin/env bash
# clean.sh — Remove generated artefacts so the pipeline re-runs from scratch.
# Safe to run anytime; only deletes files under ./artefacts/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ART="${DEMO_ROOT}/artefacts"

if [[ ! -d "${ART}" ]]; then
    echo "No artefacts directory at ${ART}; nothing to clean."
    exit 0
fi

echo "==> Removing artefacts under ${ART}"
find "${ART}" -mindepth 1 -maxdepth 1 \
    \( -name "*.onnx" -o -name "*.json" -o -name "*.compiled" \
       -o -name "*.key" -o -name "*.srs" -o -name "kzg*.srs" \) \
    -print -delete || true

echo "==> Clean. Re-run scripts/run-all.sh to rebuild."
