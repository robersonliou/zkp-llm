#!/usr/bin/env bash
# 05-verify.sh — stage 05 of the Demo B pipeline.
#
# Three modes:
#   --mock-mode : header sniff for `MOCKPRF\0` magic, cross-check pre/post
#                 roots in step.public.json against step.{pre,post}.hash.
#   --dev-mode  : `RISC0_DEV_MODE=1 cargo risczero verify --path step.proof.bin <image_id>`.
#                 cargo-risczero 2.3.2 ships the dev verifier; with the env
#                 var set it accepts the dev placeholder seal produced by
#                 stage 04 and confirms image_id + journal commitments.
#   --full      : OUT OF SCOPE — would run cargo risczero verify without
#                 RISC0_DEV_MODE.
#
# Recording-facing success lines:
#   [MOCK]     step.proof.bin verified: pre_root↔post_root match, mcycle_count=<N>
#   [DEV-REAL] step.proof.bin verified: pre_root↔post_root match, mcycle=<N>, dev-receipt=true
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ART="${DEMO_ROOT}/artefacts"
DIST="${DEMO_ROOT}/dist"

PROOF="${ART}/step.proof.bin"
PUBLIC="${ART}/step.public.json"
IMAGE_ID_FILE="${DIST}/cartesi-risc0-guest-step-prover-image-id.txt"

MODE=""
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
# If still unset, fall back to header sniff to auto-detect mock seals.
if [[ -z "${MODE}" ]]; then
    HEADER="$(head -c 8 "${PROOF}" 2>/dev/null | tr -d '\0' || true)"
    if [[ "${HEADER}" == "MOCKPRF" ]]; then
        MODE="mock"
    else
        MODE="dev"
    fi
fi

if [[ ! -f "${PROOF}" ]]; then
    echo "ERROR: missing ${PROOF}; run 04-prove.sh first" >&2
    exit 1
fi
if [[ ! -f "${PUBLIC}" ]]; then
    echo "ERROR: missing ${PUBLIC}; run 04-prove.sh first" >&2
    exit 1
fi

case "${MODE}" in
mock)
    HEADER="$(head -c 8 "${PROOF}" 2>/dev/null | tr -d '\0' || true)"
    if [[ "${HEADER}" != "MOCKPRF" ]]; then
        echo "ERROR: --mock-mode but step.proof.bin lacks MOCKPRF header (got '${HEADER}')" >&2
        echo "       Re-run scripts/04-prove.sh --mock-mode to regenerate." >&2
        exit 1
    fi
    echo "==> [05/MOCK] Verifying step.proof.bin (mock STARK seal)"

    PRE_ROOT="$(jq -r '.pre_root // .pre_hash // empty'  "${PUBLIC}" 2>/dev/null || true)"
    POST_ROOT="$(jq -r '.post_root // .post_hash // empty' "${PUBLIC}" 2>/dev/null || true)"
    MCYCLE="$(jq -r '.mcycle // .mcycle_count // 100' "${PUBLIC}" 2>/dev/null || echo 100)"

    if [[ -z "${PRE_ROOT}" || -z "${POST_ROOT}" ]]; then
        echo "ERROR: step.public.json missing pre_root/post_root fields" >&2
        exit 1
    fi

    PRE_FILE="${ART}/step.pre.hash"
    POST_FILE="${ART}/step.post.hash"
    if [[ -f "${PRE_FILE}" && -f "${POST_FILE}" ]]; then
        PRE_DISK=$(tr -d '[:space:]' < "${PRE_FILE}")
        POST_DISK=$(tr -d '[:space:]' < "${POST_FILE}")
        if [[ "${PRE_ROOT}"  != "${PRE_DISK}"  ]]; then
            echo "ERROR: pre_root mismatch: public.json=${PRE_ROOT} vs hash file=${PRE_DISK}" >&2
            exit 1
        fi
        if [[ "${POST_ROOT}" != "${POST_DISK}" ]]; then
            echo "ERROR: post_root mismatch: public.json=${POST_ROOT} vs hash file=${POST_DISK}" >&2
            exit 1
        fi
    fi

    SZ=$(stat -c '%s' "${PROOF}" 2>/dev/null || stat -f '%z' "${PROOF}")
    echo "    proof_size=${SZ} bytes"
    echo "    magic=MOCKPRF (8 bytes) ok"
    echo "    pre_root=${PRE_ROOT}"
    echo "    post_root=${POST_ROOT}"
    echo "[MOCK] step.proof.bin verified: pre_root↔post_root match, mcycle_count=${MCYCLE}"
    echo "==> [05/MOCK] OK"
    ;;

dev)
    if ! command -v cargo >/dev/null 2>&1; then
        echo "ERROR: cargo not in PATH; cannot run cargo risczero verify." >&2
        exit 2
    fi
    [[ -f "${IMAGE_ID_FILE}" ]] || {
        echo "ERROR: image-id file missing at ${IMAGE_ID_FILE}; run 01 first" >&2
        exit 3
    }
    IMAGE_ID="$(tr -d '[:space:]' < "${IMAGE_ID_FILE}")"

    PRE_ROOT="$(jq -r '.pre_root  // empty' "${PUBLIC}" 2>/dev/null || true)"
    POST_ROOT="$(jq -r '.post_root // empty' "${PUBLIC}" 2>/dev/null || true)"
    MCYCLE="$(jq -r '.mcycle // .mcycle_count // 0' "${PUBLIC}" 2>/dev/null || echo 0)"

    echo "==> [05/DEV] cargo risczero verify --path step.proof.bin ${IMAGE_ID}"
    if ! RISC0_DEV_MODE=1 cargo risczero verify \
            --path "${PROOF}" \
            "${IMAGE_ID}" 2>&1 | sed 's/^/    /'; then
        echo "ERROR: cargo risczero verify failed on the dev receipt." >&2
        echo "       Check that 04-prove.sh ran with RISC0_DEV_MODE=1 and that" >&2
        echo "       the image_id at ${IMAGE_ID_FILE} matches the prover bin." >&2
        exit 4
    fi

    # Cross-check pre/post roots in the public manifest against the hash files
    # (defence in depth — catches the case where 03 and 04 wrote inconsistent
    # JSON+disk, which would be a bug in our scripts).
    PRE_FILE="${ART}/step.pre.hash"
    POST_FILE="${ART}/step.post.hash"
    if [[ -f "${PRE_FILE}" && -f "${POST_FILE}" ]]; then
        PRE_DISK=$(tr -d '[:space:]' < "${PRE_FILE}")
        POST_DISK=$(tr -d '[:space:]' < "${POST_FILE}")
        if [[ "${PRE_ROOT}" != "${PRE_DISK}" || "${POST_ROOT}" != "${POST_DISK}" ]]; then
            echo "ERROR: pre/post root mismatch between public.json and hash files." >&2
            echo "       public.json: ${PRE_ROOT} / ${POST_ROOT}" >&2
            echo "       hash files : ${PRE_DISK} / ${POST_DISK}" >&2
            exit 5
        fi
    fi

    SZ=$(stat -c '%s' "${PROOF}" 2>/dev/null || stat -f '%z' "${PROOF}")
    echo
    echo "    proof_size=${SZ} bytes (dev receipt, NOT a real STARK seal)"
    echo "    image_id=${IMAGE_ID}"
    echo "    pre_root=${PRE_ROOT}"
    echo "    post_root=${POST_ROOT}"
    echo "[DEV-REAL] step.proof.bin verified: pre_root↔post_root match, mcycle=${MCYCLE}, dev-receipt=true"
    echo "==> [05/DEV] OK"
    ;;

full)
    echo "==> [05/FULL] not implemented in this PoC."
    echo "    Would invoke 'cargo risczero verify' against a real STARK seal."
    ;;
esac

exit 0
