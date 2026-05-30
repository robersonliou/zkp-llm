#!/usr/bin/env bash
# 03-collect-step.sh — stage 03 of the Demo B pipeline.
#
# Three modes:
#   --mock-mode : 5 dense uarch hashes from /dev/urandom + JSON skeleton.
#   --dev-mode  : real `cartesi-machine --load=... --max-mcycle=1 --log-step=1,FILE`
#                 against the snapshot from stage 02. Pre/post root hashes
#                 are extracted from the v0.20.0 step-log binary header
#                 (32 B pre_root || 8 B mcycle_count LE || 32 B post_root ||
#                  the rest of the per-cycle access log entries).
#                 We also dump the dense uarch hash sequence to a sibling
#                 text file so the recording can show "real hashes ticking".
#   --full      : OUT OF SCOPE. Same stub as 02.
#
# Outputs in ./artefacts/:
#   - step.pre.hash       (32-byte root hash, 0x-prefixed hex, LF)
#   - step.post.hash      (32-byte root hash, 0x-prefixed hex, LF)
#   - step.log.json       Skeleton/manifest JSON (consumed by 04 for mcycle)
#   - step.bin            (dev-mode only) raw cartesi-machine step log
#   - step.uarch-hashes.txt (dev-mode only) `mcycle,uarch: hash` lines
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ART="${DEMO_ROOT}/artefacts"
SNAP_DIR="${ART}/machine-snapshot"
mkdir -p "${ART}"

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

PRE="${ART}/step.pre.hash"
POST="${ART}/step.post.hash"
LOG="${ART}/step.log.json"
STEP_BIN="${ART}/step.bin"
UARCH_TXT="${ART}/step.uarch-hashes.txt"

case "${MODE}" in
mock)
    echo "==> [03/MOCK] emitting 5 dense uarch hashes + JSON skeleton"
    HASHES=()
    for i in 0 1 2 3 4; do
        if command -v openssl >/dev/null 2>&1; then
            h=$(openssl rand -hex 32)
        else
            h=$(head -c 32 /dev/urandom | xxd -p -c 64)
        fi
        HASHES+=("0x${h}")
        printf '    step.%d.hash=0x%s\n' "${i}" "${h}"
    done

    PRE_HASH="${HASHES[0]}"
    POST_HASH="${HASHES[4]}"
    printf '%s\n' "${PRE_HASH}"  > "${PRE}"
    printf '%s\n' "${POST_HASH}" > "${POST}"

    cat > "${LOG}" <<JSON
{
  "mock": true,
  "mode": "mock",
  "version": "v0.20.0-mock",
  "mcycle_count": 100,
  "mcycle_start": 0,
  "mcycle_end": 1,
  "uarch_cycle_count": 5,
  "hash_function": "openssl-rand-hex-32",
  "pre_root":  "${PRE_HASH}",
  "post_root": "${POST_HASH}",
  "uarch_root_hashes": [
    "${HASHES[0]}",
    "${HASHES[1]}",
    "${HASHES[2]}",
    "${HASHES[3]}",
    "${HASHES[4]}"
  ],
  "comment": "Skeleton mirroring cm_collect_uarch_cycle_root_hashes output."
}
JSON
    echo "    pre=${PRE_HASH}"
    echo "    post=${POST_HASH}"
    echo "    log=${LOG} ($(stat -c '%s' "${LOG}" 2>/dev/null || stat -f '%z' "${LOG}") bytes)"
    echo "==> [03/MOCK] OK"
    ;;

dev)
    if [[ ! -f "${SNAP_DIR}/config.json" ]]; then
        echo "ERROR: machine snapshot not found at ${SNAP_DIR}" >&2
        echo "       Run scripts/02-build-machine.sh --dev-mode first." >&2
        exit 2
    fi
    if ! command -v cartesi-machine >/dev/null 2>&1; then
        echo "ERROR: cartesi-machine CLI not in PATH" >&2
        echo "       Run scripts/02-build-machine.sh --dev-mode first." >&2
        exit 3
    fi

    rm -f "${STEP_BIN}" "${UARCH_TXT}"
    echo "==> [03/DEV] cartesi-machine --load=${SNAP_DIR} --max-mcycle=1 --log-step=1,step.bin"
    cartesi-machine \
        --load="${SNAP_DIR}" \
        --hash-tree=phtc_size:64 \
        --max-mcycle=1 \
        --log-step=1,"${STEP_BIN}" 2>&1 | tee "${UARCH_TXT}.raw" | sed 's/^/    /'

    # The cartesi-machine prints `Loading machine: please wait` and
    # `Logging step of N cycles to ...`; filter those out, keep only
    # `<mcycle>[,<uarch_cycle>]: <hex>` lines for the dense hash log.
    grep -E '^[0-9]+(,[0-9]+)?:[[:space:]]*[0-9a-fA-F]{64}$' \
        "${UARCH_TXT}.raw" > "${UARCH_TXT}" || true
    rm -f "${UARCH_TXT}.raw"

    if [[ ! -s "${STEP_BIN}" ]]; then
        echo "ERROR: ${STEP_BIN} is empty — cartesi-machine --log-step produced nothing." >&2
        exit 4
    fi

    # v0.20.0 step-log header layout:
    #   bytes 0..32   pre_root  (32 B)
    #   bytes 32..40  mcycle_count (u64 LE; the length of the logged step)
    #   bytes 40..72  post_root (32 B)
    PRE_HEX=$(xxd -p -l 32 -s 0  "${STEP_BIN}" | tr -d '\n')
    MCYCLE_HEX=$(xxd -p -l 8  -s 32 "${STEP_BIN}" | tr -d '\n')
    POST_HEX=$(xxd -p -l 32 -s 40 "${STEP_BIN}" | tr -d '\n')
    # Decode the 8-byte little-endian mcycle_count.
    MCYCLE_DEC=$(python3 -c "import sys; print(int.from_bytes(bytes.fromhex('${MCYCLE_HEX}'), 'little'))")

    PRE_HASH="0x${PRE_HEX}"
    POST_HASH="0x${POST_HEX}"
    printf '%s\n' "${PRE_HASH}"  > "${PRE}"
    printf '%s\n' "${POST_HASH}" > "${POST}"

    STEP_BIN_SIZE=$(stat -c '%s' "${STEP_BIN}" 2>/dev/null || stat -f '%z' "${STEP_BIN}")
    UARCH_LINES=$(wc -l < "${UARCH_TXT}" 2>/dev/null || echo 0)

    cat > "${LOG}" <<JSON
{
  "mock": false,
  "mode": "dev-real",
  "version": "v0.20.0",
  "mcycle_count": ${MCYCLE_DEC},
  "mcycle_count_le_hex": "${MCYCLE_HEX}",
  "pre_root":  "${PRE_HASH}",
  "post_root": "${POST_HASH}",
  "hash_function": "sha256",
  "step_bin_path": "step.bin",
  "step_bin_bytes": ${STEP_BIN_SIZE},
  "uarch_hash_lines": ${UARCH_LINES},
  "uarch_hash_file": "step.uarch-hashes.txt",
  "comment": "Real cartesi-machine v0.20.0 --log-step output; consumed by RISC0 guest prover."
}
JSON

    echo
    echo "    pre  = ${PRE_HASH}"
    echo "    post = ${POST_HASH}"
    echo "    mcycle_count = ${MCYCLE_DEC} (LE hex ${MCYCLE_HEX})"
    echo "    step.bin = ${STEP_BIN} (${STEP_BIN_SIZE} bytes)"
    echo "    log      = ${LOG}"
    echo "    uarch    = ${UARCH_TXT} (${UARCH_LINES} dense hashes)"
    echo "==> [03/DEV] OK"
    ;;

full)
    echo "==> [03/FULL] not implemented (would invoke the full prover-host loop)."
    # Defensive defaults so 04/05 don't choke if someone runs this branch.
    printf '0x%s\n' "$(printf '%064d' 0)" > "${PRE}"
    printf '0x%s\n' "$(printf '%064d' 0)" > "${POST}"
    printf '{"mock": false, "mode": "full", "note": "stub"}\n' > "${LOG}"
    ;;
esac
