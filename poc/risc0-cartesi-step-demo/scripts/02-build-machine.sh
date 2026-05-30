#!/usr/bin/env bash
# 02-build-machine.sh — stage 02 of the Demo B pipeline.
#
# Three modes (mirror run-all.sh):
#   --mock-mode  : write a stub `machine-snapshot/` dir; original Day-5 behaviour.
#   --dev-mode   : install cartesi-machine .deb if missing, then run
#                  `cartesi-machine --no-ram-image --no-root-flash-drive \
#                      --hash-tree=hash_function:sha256,phtc_size:64 \
#                      --max-mcycle=0 --store=./artefacts/machine-snapshot`
#                  The Cartesi v0.20.0 .deb does NOT ship a Linux rootfs or
#                  RAM image, so we boot a minimal (empty) machine. Each
#                  microarchitecture step is still a real state transition,
#                  which is the unit the RISC0 step prover proves.
#   --full       : OUT OF SCOPE in this PoC. Would need 16+ GB RAM and a
#                  Linux rootfs image. Exits 0 with a 'not implemented' notice.
#
# Outputs in ./artefacts/ (dev-mode):
#   - machine-snapshot/       Cartesi machine store dir (sha256 hash tree)
#   - machine-snapshot.info   Quick `du -sh` + file listing for the README.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST="${DEMO_ROOT}/dist"
ART="${DEMO_ROOT}/artefacts"
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

SNAP_DIR="${ART}/machine-snapshot"

install_cartesi_machine() {
    if command -v cartesi-machine >/dev/null 2>&1; then
        echo "    [skip] cartesi-machine already on PATH ($(cartesi-machine --version 2>&1 | head -1))"
        return 0
    fi
    case "$(uname -m)" in
        x86_64|amd64) DEB="${DIST}/machine-emulator_amd64.deb" ;;
        aarch64|arm64) DEB="${DIST}/machine-emulator_arm64.deb" ;;
        *) echo "ERROR: unsupported arch $(uname -m)" >&2; return 2 ;;
    esac
    if [[ ! -f "${DEB}" ]]; then
        echo "ERROR: ${DEB} not found. Run scripts/01-fetch-prover-bin.sh first." >&2
        return 2
    fi
    echo "    [install] ${DEB}"
    if [[ "$(id -u)" -ne 0 ]]; then
        sudo apt-get update >/dev/null 2>&1 || true
        sudo apt-get install -y --no-install-recommends "${DEB}" >/dev/null
    else
        apt-get update >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends "${DEB}" >/dev/null
    fi
}

case "${MODE}" in
mock)
    echo "==> [02/MOCK] writing stub machine-snapshot/"
    rm -rf "${SNAP_DIR}"
    mkdir -p "${SNAP_DIR}"
    printf 'stub-snapshot for risc0-cartesi-step-demo (mock mode)\n' > "${SNAP_DIR}/README"
    # Touch a placeholder config.json so downstream stages can pretend it's
    # the real layout. (Stage 03/04 in mock mode don't actually read it.)
    cat > "${SNAP_DIR}/config.json" <<'JSON'
{
  "mock": true,
  "note": "Stub snapshot; --mock-mode pipeline does not run cartesi-machine."
}
JSON
    echo "    stub snapshot at ${SNAP_DIR}"
    ls -lh "${SNAP_DIR}" | sed 's/^/    /'
    echo "==> [02/MOCK] OK"
    ;;

dev)
    echo "==> [02/DEV] installing cartesi-machine emulator if needed"
    install_cartesi_machine

    echo "==> [02/DEV] verifying bundled paths in /usr/share/cartesi-machine/"
    ls -la /usr/share/cartesi-machine/ /usr/share/cartesi-machine/uarch/ 2>/dev/null | sed 's/^/    /' || true
    # Note: /usr/share/cartesi-machine/images/ is empty in the v0.20.0 .deb —
    # the release does NOT ship linux.bin/rootfs.ext2, so we cannot boot
    # /bin/echo as the plan originally envisaged. The fallback is the
    # minimal-machine approach below, which still exercises real cartesi-
    # machine state-transition proving (one mcycle = one real microarch
    # transition through uarch-ram.bin).

    echo "==> [02/DEV] creating minimal cartesi-machine snapshot (sha256 hash tree)"
    rm -rf "${SNAP_DIR}"
    # The RISC0 guest prover image expects the step log header to be hashed
    # under sha256 ("hash_tree_target must be 1" panic if we use keccak256).
    # phtc_size:64 keeps the page-hash-tree cache under 1 MB; the default
    # (2048) blows it up to ~50 MB which is wasteful for a 1-mcycle demo.
    if ! cartesi-machine \
            --no-ram-image \
            --no-root-flash-drive \
            --hash-tree=hash_function:sha256,phtc_size:64 \
            --max-mcycle=0 \
            --store="${SNAP_DIR}" 2>&1 | sed 's/^/    /'; then
        echo "ERROR: cartesi-machine snapshot creation failed." >&2
        echo "       Check that the .deb installed correctly above." >&2
        exit 3
    fi

    if [[ ! -f "${SNAP_DIR}/config.json" ]]; then
        echo "ERROR: snapshot missing config.json — store did not complete." >&2
        exit 4
    fi

    SNAP_SIZE_HUMAN="$(du -sh "${SNAP_DIR}" 2>/dev/null | cut -f1)"
    SNAP_SIZE_BYTES="$(du -sb "${SNAP_DIR}" 2>/dev/null | cut -f1)"
    echo "==> [02/DEV] OK — snapshot=${SNAP_DIR} (${SNAP_SIZE_HUMAN})"
    {
        echo "snapshot_dir=${SNAP_DIR}"
        echo "size_human=${SNAP_SIZE_HUMAN}"
        echo "size_bytes=${SNAP_SIZE_BYTES}"
        echo "hash_function=sha256"
        echo "phtc_size=64"
        echo "max_mcycle=0"
        echo "files:"
        ls -la "${SNAP_DIR}" | sed 's/^/  /'
    } > "${ART}/machine-snapshot.info"
    cat "${ART}/machine-snapshot.info" | sed 's/^/    /'
    ;;

full)
    echo "==> [02/FULL] not implemented in this PoC."
    echo "    The --full path would need a real Linux rootfs (~50 MB) plus"
    echo "    ~16 GB free RAM for r0vm to STARK-prove a single mcycle."
    echo "    Use --dev-mode for real Cartesi+RISC0 within laptop budget."
    rm -rf "${SNAP_DIR}"
    mkdir -p "${SNAP_DIR}"
    printf 'full-mode stub: out of scope for this PoC (needs ≥16 GB RAM)\n' \
        > "${SNAP_DIR}/README"
    ;;
esac
