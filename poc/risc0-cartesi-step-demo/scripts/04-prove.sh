#!/usr/bin/env bash
# 04-prove.sh — stage 04 of the Demo B pipeline.
#
# Three modes:
#   --mock-mode : write 264 B step.proof.bin with `MOCKPRF\0` magic header +
#                 256 random bytes. step.public.json gets mode="mock".
#   --dev-mode  : `RISC0_DEV_MODE=1 r0vm --elf cartesi-risc0-guest-step-prover.bin
#                  --initial-input step.bin --receipt step.proof.bin`
#                  The cartesi-risc0-guest-step-prover.bin is the official
#                  v0.20.0 release guest. RISC0_DEV_MODE=1 swaps the real
#                  STARK prover for a dev one — the receipt verifies with
#                  RISC0_DEV_MODE=1 set on the verifier side, but is NOT
#                  cryptographically sound. This still exercises the entire
#                  guest+host loop (image_id matches, step-log binary parses,
#                  pre/post roots round-trip through the journal).
#   --full      : OUT OF SCOPE — would invoke r0vm without RISC0_DEV_MODE
#                 (needs 16+ GB RAM). Stays as a stub.
#
# Outputs in ./artefacts/:
#   - step.proof.bin       (RISC0 receipt; ~400 B in dev mode, 264 B mock)
#   - step.public.json     {mode, image_id, pre_root, post_root, mcycle, ...}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ART="${DEMO_ROOT}/artefacts"
DIST="${DEMO_ROOT}/dist"

PRE="${ART}/step.pre.hash"
POST="${ART}/step.post.hash"
LOG="${ART}/step.log.json"
STEP_BIN="${ART}/step.bin"
PROOF="${ART}/step.proof.bin"
PUBLIC="${ART}/step.public.json"

PROVER_BIN="${DIST}/cartesi-risc0-guest-step-prover.bin"
IMAGE_ID_FILE="${DIST}/cartesi-risc0-guest-step-prover-image-id.txt"

MODE="mock"
if [[ "${DEV_MODE:-0}" == "1" ]]; then MODE="dev"; fi
if [[ "${MOCK_PROVER:-0}" == "1" ]]; then MODE="mock"; fi
for arg in "$@"; do
    case "${arg}" in
        --mock-mode|--mock) MODE="mock" ;;
        --dev-mode|--dev)   MODE="dev"  ;;
        --full)             MODE="full" ;;
        -h|--help) echo "Usage: $0 [--mock-mode | --dev-mode | --full]"; exit 0 ;;
    esac
done

for f in "${PRE}" "${POST}" "${LOG}"; do
    [[ -f "${f}" ]] || { echo "ERROR: missing ${f}; run 03-collect-step.sh first" >&2; exit 2; }
done

PRE_HASH=$(tr -d '[:space:]' < "${PRE}")
POST_HASH=$(tr -d '[:space:]' < "${POST}")
IMAGE_ID="$(tr -d '[:space:]' < "${IMAGE_ID_FILE}" 2>/dev/null || echo "0xunknown")"
# jq is present in the runtime image; default mcycle to 100 if for any reason
# the field is missing.
MCYCLE=$(jq -r '.mcycle_count // 100' "${LOG}" 2>/dev/null || echo 100)

case "${MODE}" in
mock)
    echo "==> [04/MOCK] writing 264-byte MOCKPRF-magic step.proof.bin"
    echo "    image=${PROVER_BIN}"
    echo "    image_id=${IMAGE_ID}"
    echo "    pre_root=${PRE_HASH}"
    echo "    post_root=${POST_HASH}"
    echo "    mcycle_count=${MCYCLE}"
    {
        printf 'MOCKPRF\x00'
        if command -v openssl >/dev/null 2>&1; then
            openssl rand 256
        else
            head -c 256 /dev/urandom
        fi
    } > "${PROOF}"
    cat > "${PUBLIC}" <<JSON
{
  "mode": "mock",
  "image_id": "${IMAGE_ID}",
  "pre_root":  "${PRE_HASH}",
  "post_root": "${POST_HASH}",
  "mcycle":    ${MCYCLE},
  "note": "Hybrid PoC: stages 02-05 mocked; real cryptography proved in stage 00."
}
JSON
    PROOF_SIZE=$(stat -c '%s' "${PROOF}" 2>/dev/null || stat -f '%z' "${PROOF}")
    echo "    -> ${PROOF} (${PROOF_SIZE} bytes)"
    echo "    -> ${PUBLIC}"
    echo "==> [04/MOCK] OK"
    ;;

dev)
    if [[ ! -f "${PROVER_BIN}" ]]; then
        echo "ERROR: prover binary missing at ${PROVER_BIN}" >&2
        echo "       Run scripts/01-fetch-prover-bin.sh first." >&2
        exit 3
    fi
    if [[ ! -f "${STEP_BIN}" ]]; then
        echo "ERROR: step log binary missing at ${STEP_BIN}" >&2
        echo "       Run scripts/03-collect-step.sh --dev-mode first." >&2
        exit 4
    fi
    if ! command -v r0vm >/dev/null 2>&1; then
        echo "ERROR: r0vm not in PATH (cargo-risczero not installed)" >&2
        exit 5
    fi

    echo "==> [04/DEV] RISC0_DEV_MODE=1 r0vm --elf ${PROVER_BIN##*/} --initial-input step.bin --receipt step.proof.bin"
    echo "    image=${PROVER_BIN}"
    echo "    image_id=${IMAGE_ID}"
    echo "    step.bin=${STEP_BIN} ($(stat -c '%s' "${STEP_BIN}" 2>/dev/null) bytes)"
    echo "    pre_root=${PRE_HASH}"
    echo "    post_root=${POST_HASH}"
    echo "    mcycle_count=${MCYCLE}"

    # We intentionally feed the step-log binary as `--initial-input`. The
    # R0BF-wrapped guest image at ${PROVER_BIN} reads the v0.20.0 step log
    # from this input, recomputes the pre/post root hashes inside the zkVM,
    # and commits them to the receipt journal.
    if ! RISC0_DEV_MODE=1 r0vm \
            --elf "${PROVER_BIN}" \
            --initial-input "${STEP_BIN}" \
            --receipt "${PROOF}" 2>&1 | sed 's/^/    /'; then
        echo "ERROR: r0vm (dev) failed. Common causes:" >&2
        echo "       - cartesi-machine snapshot uses keccak256 instead of sha256" >&2
        echo "         (the guest panics with 'hash_tree_target must be 1')" >&2
        echo "       - step.bin produced by a non-v0.20.0 cartesi-machine" >&2
        echo "       - prover bin version mismatch with r0vm 2.x" >&2
        exit 6
    fi

    PROOF_SIZE=$(stat -c '%s' "${PROOF}" 2>/dev/null || stat -f '%z' "${PROOF}")
    cat > "${PUBLIC}" <<JSON
{
  "mode": "dev-real",
  "image_id": "${IMAGE_ID}",
  "pre_root":  "${PRE_HASH}",
  "post_root": "${POST_HASH}",
  "mcycle":    ${MCYCLE},
  "dev_receipt": true,
  "receipt_bytes": ${PROOF_SIZE},
  "note": "Real r0vm 2.3.2 with RISC0_DEV_MODE=1 — receipt is a dev placeholder, NOT cryptographically sound."
}
JSON
    echo
    echo "    -> ${PROOF} (${PROOF_SIZE} bytes) [DEV receipt, not a real STARK seal]"
    echo "    -> ${PUBLIC}"
    echo "==> [04/DEV] OK"
    ;;

full)
    echo "==> [04/FULL] not implemented in this PoC (needs ≥16 GB RAM)."
    # Write a stub receipt + public so 05 still has something to look at.
    printf 'FULLSTUB' > "${PROOF}"
    cat > "${PUBLIC}" <<JSON
{
  "mode": "full-stub",
  "image_id": "${IMAGE_ID}",
  "pre_root":  "${PRE_HASH}",
  "post_root": "${POST_HASH}",
  "mcycle":    ${MCYCLE},
  "note": "--full path is not implemented; use --dev-mode for real Cartesi+RISC0."
}
JSON
    ;;
esac
