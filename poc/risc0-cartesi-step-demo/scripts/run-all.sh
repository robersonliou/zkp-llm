#!/usr/bin/env bash
# run-all.sh — Demo B end-to-end driver. Three modes, all share the same
# stages 00 + 01 (real); they differ only in how stages 02–05 are realised:
#
#   --mock-mode   (DEFAULT, recording-friendly, ~74 s, < 1 GB RAM)
#     - Stage 00: REAL RISC0 hello-world prove + verify (cargo-risczero).
#     - Stage 01: REAL download of the Cartesi v0.20.0 release prover bin.
#     - Stage 02-05: MOCK pipeline (snapshot stub, openssl random hashes,
#       264 B `MOCKPRF`-magic proof, header+root cross-check verify).
#
#   --dev-mode    (NEW in tier-2; ~3-5 min, 3-5 GB RAM peak)
#     - Stage 00, 01: same REAL paths as mock-mode.
#     - Stage 02: REAL `cartesi-machine ... --store=machine-snapshot` using
#       `--no-ram-image --no-root-flash-drive --hash-tree=hash_function:sha256`.
#       The .deb does NOT ship a Linux rootfs, so we boot a minimal machine
#       (sufficient for state-transition proving since each mcycle is a real
#       microarchitecture transition).
#     - Stage 03: REAL `cartesi-machine --log-step=1,step.bin` produces the
#       v0.20.0 step log binary that the prover guest consumes. We also
#       extract pre/post root hashes and write `step.log.json` metadata.
#     - Stage 04: REAL `RISC0_DEV_MODE=1 r0vm` against the official
#       `cartesi-risc0-guest-step-prover.bin`. Receipt is a dev seal (no real
#       STARK; ~393 bytes) but exercises the whole guest + host loop.
#     - Stage 05: REAL `cargo risczero verify` against the dev receipt.
#
#   --full        (out of scope for this PoC; needs ≥16 GB RAM)
#     - Same as --dev-mode but without RISC0_DEV_MODE. Currently exits with
#       a "not implemented in this PoC" message; stub left for future.
#
# Why three modes? Recording day is laptop-bound (15 GB RAM total, 11 GB free),
# but reviewers should see the real Cartesi-machine snapshot + real RISC0
# dev-receipt pipeline at least once. Mock keeps the recording promise; dev
# makes the cryptography commitments real (sha256 hash tree, R0BF guest
# image, sha256 step log) without paying the full STARK prove cost.
#
# Usage:
#   ./scripts/run-all.sh                  # default == --mock-mode
#   ./scripts/run-all.sh --mock-mode      # explicit mock (laptop, ~1 GB RAM)
#   ./scripts/run-all.sh --dev-mode       # NEW: real Cartesi + dev RISC0 (~3-5 GB)
#   ./scripts/run-all.sh --full           # placeholder for 16+ GB workstation
#   MOCK_PROVER=1 ./scripts/run-all.sh    # equivalent to --mock-mode
#   DEV_MODE=1    ./scripts/run-all.sh    # equivalent to --dev-mode
#
# Output: /work/artefacts/{risc0-hello-world.{log,receipt.bin},
#                          step.pre.hash, step.post.hash, step.log.json,
#                          step.proof.bin, step.public.json,
#                          machine-snapshot/ (dev-mode only),
#                          step.bin (dev-mode only — raw cartesi log)}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mode resolution. Precedence: explicit CLI flag > env var > default mock.
MODE=""
if [[ "${DEV_MODE:-0}" == "1" ]]; then
    MODE="dev"
elif [[ "${MOCK_PROVER:-0}" == "1" ]]; then
    MODE="mock"
fi
for arg in "$@"; do
    case "${arg}" in
        --mock-mode|--mock)
            MODE="mock"
            ;;
        --dev-mode|--dev)
            MODE="dev"
            ;;
        --full)
            MODE="full"
            ;;
        -h|--help)
            sed -n '2,55p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
    esac
done
if [[ -z "${MODE}" ]]; then
    MODE="mock"
fi

# Export the mode envs so child scripts can branch without re-parsing argv.
export MOCK_PROVER=0
export DEV_MODE=0
MOCK_FLAG=""
case "${MODE}" in
    mock) export MOCK_PROVER=1; MOCK_FLAG="--mock-mode" ;;
    dev)  export DEV_MODE=1 ;;
    full) : ;;
esac

# Mode banner — show what's about to run and the rough RAM expectation. The
# resource estimates come from observed runs (mock: tier-1 baseline) and from
# the cartesi-machine + r0vm dev-mode test (RAM peak ~3 GB observed) plus
# release-notes guidance for full mode (≥16 GB).
echo "######################################################################"
case "${MODE}" in
    mock)
        echo "# Mode: --mock-mode (DEFAULT, recording-ready)                        #"
        echo "#   Stages 00, 01    : REAL crypto (RISC0 hello-world + release fetch)#"
        echo "#   Stages 02-05     : MOCK (shape-only; magic-header proof)          #"
        echo "#   Expected resource: ~1 GB RAM, ~74 s wall time on a laptop         #"
        ;;
    dev)
        echo "# Mode: --dev-mode (NEW; tier-2 dev-real upgrade)                     #"
        echo "#   Stages 00, 01    : REAL crypto                                    #"
        echo "#   Stages 02-05     : REAL Cartesi pipeline + RISC0_DEV_MODE=1       #"
        echo "#     02: real cartesi-machine snapshot (sha256 hash tree)            #"
        echo "#     03: real cartesi-machine --log-step (binary v0.20.0 step log)   #"
        echo "#     04: real r0vm dev prove (no STARK seal, fast)                   #"
        echo "#     05: real cargo risczero verify (dev receipt)                    #"
        echo "#   Expected resource: ~3-5 GB RAM, ~3-5 min wall time                #"
        ;;
    full)
        echo "# Mode: --full (placeholder; OUT OF SCOPE for this PoC)               #"
        echo "#   Would run the entire pipeline with a real STARK seal in stage 04. #"
        echo "#   Needs ≥16 GB free RAM. This branch exits 0 from each stub stage   #"
        echo "#   with a 'not implemented' notice; --dev-mode is the supported path #"
        echo "#   for exercising real Cartesi+RISC0 on a laptop.                    #"
        ;;
esac
echo "######################################################################"
echo

run_step() {
    local label="$1"; shift
    echo "######  ${label}  ######"
    if ! "$@"; then
        local ec=$?
        echo "ERROR: ${label} failed (exit ${ec})" >&2
        return ${ec}
    fi
    echo
}

# Stage 00: REAL crypto (RISC0 hello-world). Runs in every mode.
run_step "00 risc0 hello-world (REAL crypto)" "${SCRIPT_DIR}/00-risc0-hello-world.sh"

# Stage 01: REAL fetch in every mode (cache hit makes it ~instant on rerun).
if [[ ! -f "${SCRIPT_DIR}/../dist/cartesi-risc0-guest-step-prover.bin" ]]; then
    run_step "01 fetch prover bin (REAL download)"  "${SCRIPT_DIR}/01-fetch-prover-bin.sh" || true
else
    echo "######  01 fetch prover bin (skipped: already cached)  ######"
    echo
fi

# Stages 02-05 dispatch by mode. Each child script ALSO inspects its own
# argv + env so it can be invoked standalone (e.g.
# `DEV_MODE=1 bash scripts/03-collect-step.sh`).
case "${MODE}" in
    mock)
        run_step "02 build machine (MOCK stub)" "${SCRIPT_DIR}/02-build-machine.sh" ${MOCK_FLAG} || true
        run_step "03 collect step (MOCK)"      "${SCRIPT_DIR}/03-collect-step.sh"   ${MOCK_FLAG}
        run_step "04 prove (MOCK magic seal)"  "${SCRIPT_DIR}/04-prove.sh"          ${MOCK_FLAG}
        run_step "05 verify (MOCK header check)" "${SCRIPT_DIR}/05-verify.sh"
        ;;
    dev)
        run_step "02 build machine (REAL cartesi-machine)" "${SCRIPT_DIR}/02-build-machine.sh" --dev-mode
        run_step "03 collect step (REAL --log-step)"        "${SCRIPT_DIR}/03-collect-step.sh"  --dev-mode
        run_step "04 prove (REAL r0vm dev receipt)"         "${SCRIPT_DIR}/04-prove.sh"         --dev-mode
        run_step "05 verify (REAL cargo risczero verify)"   "${SCRIPT_DIR}/05-verify.sh"        --dev-mode
        ;;
    full)
        run_step "02 build machine (--full STUB)" "${SCRIPT_DIR}/02-build-machine.sh" --full || true
        run_step "03 collect step (--full STUB)"  "${SCRIPT_DIR}/03-collect-step.sh"  --full || true
        run_step "04 prove (--full STUB)"         "${SCRIPT_DIR}/04-prove.sh"         --full || true
        run_step "05 verify (--full STUB)"        "${SCRIPT_DIR}/05-verify.sh"        --full || true
        ;;
esac

echo "######################################################################"
echo "# Pipeline complete (mode=${MODE}). Artefacts:"
ls -lh "${SCRIPT_DIR}/../artefacts" 2>/dev/null | sed 's/^/#   /'
echo "######################################################################"
