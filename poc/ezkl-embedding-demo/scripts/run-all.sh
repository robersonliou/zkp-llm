#!/usr/bin/env bash
# run-all.sh — End-to-end EZKL embedding demo (Demo A).
#
# Inside the container the source tree lives at /work; outside, the script
# auto-detects the demo root so it works on bare-metal too.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${DEMO_ROOT}"

mkdir -p artefacts

PY=${PYTHON:-python3}

if ! "${PY}" -c "import ezkl" >/dev/null 2>&1; then
    echo "ERROR: 'ezkl' Python package not importable with ${PY}" >&2
    echo "       Hint: pip install -r requirements.txt" >&2
    exit 2
fi

echo "==> [01/04] Generating tiny embedding ONNX..."
"${PY}" src/01_make_model.py

echo "==> [02/04] EZKL settings + calibrate + compile + SRS + setup..."
"${PY}" src/02_setup.py

echo "==> [03/04] Witness + proof..."
"${PY}" src/03_prove.py

echo "==> [04/04] Verifying proof..."
"${PY}" src/04_verify.py

echo
echo "==> DONE. Artefacts under ${DEMO_ROOT}/artefacts/:"
ls -lh artefacts/ | sed 's/^/    /'
