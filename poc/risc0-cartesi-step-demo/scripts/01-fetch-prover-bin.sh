#!/usr/bin/env bash
# 01-fetch-prover-bin.sh
# Pulls the RISC0 guest step-prover binary + image id + machine-emulator .deb
# from the cartesi/machine-emulator v0.20.0 GitHub release assets.
#
# Assets (per https://github.com/cartesi/machine-emulator/releases/tag/v0.20.0):
#   - cartesi-risc0-guest-step-prover.bin            (~ 868 KB)
#   - cartesi-risc0-guest-step-prover-image-id.txt   (~ 1 KB)
#   - machine-emulator_amd64.deb                     (~55 MB) or _arm64.deb
#
# All files land in ./dist/ at the demo root. Re-runs skip already-downloaded
# files unless --force is passed.
set -euo pipefail

RELEASE_TAG="${CARTESI_RELEASE_TAG:-v0.20.0}"
BASE_URL="https://github.com/cartesi/machine-emulator/releases/download/${RELEASE_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST="${DEMO_ROOT}/dist"
mkdir -p "${DIST}"

FORCE=0
for arg in "$@"; do
    case "${arg}" in
        --force) FORCE=1 ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo "  Fetches prover binary + image-id + machine-emulator deb."
            echo "  Set CARTESI_RELEASE_TAG to override (default: v0.20.0)."
            exit 0
            ;;
    esac
done

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64)   DEB_ASSET="machine-emulator_amd64.deb"; EXPECTED_DEB_MIN=$((40*1024*1024)) ;;
    aarch64|arm64)  DEB_ASSET="machine-emulator_arm64.deb"; EXPECTED_DEB_MIN=$((40*1024*1024)) ;;
    *)
        echo "ERROR: unsupported host arch '${ARCH}' for machine-emulator deb" >&2
        echo "       Expected x86_64 or aarch64; got '${ARCH}'." >&2
        exit 2
        ;;
esac

ASSETS=(
    "cartesi-risc0-guest-step-prover.bin"
    "cartesi-risc0-guest-step-prover-image-id.txt"
    "${DEB_ASSET}"
)

fetch_one() {
    local asset="$1"
    local out="${DIST}/${asset}"
    if [[ -f "${out}" && "${FORCE}" -eq 0 ]]; then
        echo "    [skip] ${asset} already at ${out}"
        return
    fi
    echo "    [GET ] ${BASE_URL}/${asset}"
    if ! curl -L --fail --retry 3 --retry-delay 2 \
            -o "${out}.partial" \
            "${BASE_URL}/${asset}"; then
        echo "ERROR: failed to download ${asset} from ${BASE_URL}" >&2
        echo "       Check that release tag '${RELEASE_TAG}' exists." >&2
        rm -f "${out}.partial"
        exit 3
    fi
    mv "${out}.partial" "${out}"
}

echo "==> [01] Fetching Cartesi v0.20.0 release assets to ${DIST}"
for a in "${ASSETS[@]}"; do
    fetch_one "${a}"
done

# Post-fetch sanity checks (sizes per the release-asset table).
PROVER_BIN="${DIST}/cartesi-risc0-guest-step-prover.bin"
prover_size=$(stat -c '%s' "${PROVER_BIN}" 2>/dev/null || stat -f '%z' "${PROVER_BIN}")
if [[ "${prover_size}" -lt 500000 || "${prover_size}" -gt 5000000 ]]; then
    echo "WARN: prover bin size ${prover_size} outside expected ~868 KB band." >&2
    echo "      Continuing; the binary will be sanity-checked again at prove time." >&2
fi

deb_path="${DIST}/${DEB_ASSET}"
deb_size=$(stat -c '%s' "${deb_path}" 2>/dev/null || stat -f '%z' "${deb_path}")
if [[ "${deb_size}" -lt "${EXPECTED_DEB_MIN}" ]]; then
    echo "ERROR: ${DEB_ASSET} is only ${deb_size} bytes; expected >= ${EXPECTED_DEB_MIN}." >&2
    echo "       Likely an HTML error page got saved instead of the .deb." >&2
    exit 4
fi

# image-id is a hex string; trim any trailing whitespace.
IMAGE_ID_FILE="${DIST}/cartesi-risc0-guest-step-prover-image-id.txt"
image_id="$(tr -d '[:space:]' < "${IMAGE_ID_FILE}")"
if [[ ! "${image_id}" =~ ^[0-9a-fA-F]{16,}$ ]]; then
    echo "WARN: image-id file content does not look like a hex digest: '${image_id}'" >&2
fi

echo
echo "==> Fetched assets:"
ls -lh "${DIST}" | sed 's/^/    /'
echo
echo "==> Prover image id: ${image_id}"
echo "==> [01] OK"
