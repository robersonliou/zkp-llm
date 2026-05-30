#!/usr/bin/env bash
# 00-risc0-hello-world.sh
# Real RISC0 zkVM end-to-end: scaffold a fresh `cargo risczero new` project,
# build the guest, run the host (which proves + verifies a tiny `multiply`
# computation), and dump receipt + stdout into ./artefacts/.
#
# This stage is intentionally REAL crypto: it gives the recording / slides a
# verifier-success line that is not a stub. Stages 02-05 of run-all.sh remain
# Cartesi-step mock by default (see run-all.sh --full for the heavy path).
#
# Outputs in /work/artefacts/:
#   - risc0-hello-world.log         (full host stdout incl. "verified")
#   - risc0-hello-world.receipt.bin (bincode-serialised receipt; ~150 KB - 2 MB)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ART="${DEMO_ROOT}/artefacts"
PROJ="/work/risc0-hello-world"

mkdir -p "${ART}"

echo "==> [00/05] Real RISC0 hello-world prove + verify..."

if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo not in PATH; the Docker image is supposed to ship the" >&2
    echo "       rustup toolchain at /opt/cargo. PATH=${PATH}" >&2
    exit 2
fi

if ! command -v cargo-risczero >/dev/null 2>&1; then
    echo "ERROR: cargo-risczero not in PATH; the Docker builder stage installs" >&2
    echo "       it via 'cargo install cargo-risczero --version 2.3.2 --locked'." >&2
    echo "       Rebuild the image, or re-run run-all.sh with --skip-00 (not yet" >&2
    echo "       implemented; for now, comment stage 00 out of run-all.sh)." >&2
    exit 3
fi

if [[ ! -d "${PROJ}" ]]; then
    echo "    -> scaffolding new RISC0 project at ${PROJ}"
    SCAFFOLD_PARENT="$(dirname "${PROJ}")"
    mkdir -p "${SCAFFOLD_PARENT}"
    pushd "${SCAFFOLD_PARENT}" >/dev/null

    if ! cargo risczero new --guest-name multiply hello-world 2>&1 | tee "${ART}/risc0-hello-world.scaffold.log"; then
        echo "ERROR: 'cargo risczero new' failed; see ${ART}/risc0-hello-world.scaffold.log" >&2
        popd >/dev/null
        exit 4
    fi
    mv hello-world "${PROJ}"
    popd >/dev/null

    HOST_MAIN="${PROJ}/host/src/main.rs"
    if [[ -f "${HOST_MAIN}" ]] && ! grep -q "risc0-hello-world.receipt.bin" "${HOST_MAIN}"; then
        echo "    -> patching host/src/main.rs to serialise receipt + print success"
        # The cargo-risczero template's host main.rs calls receipt.verify(MULTIPLY_ID).unwrap()
        # silently and then exits. We inject (a) a bincode::serialize of the
        # receipt to /work/artefacts/, and (b) an explicit "VERIFIER SUCCESS"
        # print, so the recording terminal shows a green-light line and the
        # downstream grep in this script can confirm we ran past .verify().
        # The patch is appended just before the closing `}` of `fn main()` so
        # it runs after the template's own verify call has already validated
        # the receipt.
        python3 - "${HOST_MAIN}" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
patch = (
    "    // --- patched by scripts/00-risc0-hello-world.sh ---\n"
    "    if let Ok(bytes) = bincode::serialize(&receipt) {\n"
    "        let out = std::path::Path::new(\"/work/artefacts/risc0-hello-world.receipt.bin\");\n"
    "        if let Some(parent) = out.parent() { let _ = std::fs::create_dir_all(parent); }\n"
    "        match std::fs::write(out, &bytes) {\n"
    "            Ok(_) => println!(\"[00] receipt serialised: {} ({} bytes)\", out.display(), bytes.len()),\n"
    "            Err(e) => eprintln!(\"[00] WARN: could not write receipt: {}\", e),\n"
    "        }\n"
    "    } else {\n"
    "        eprintln!(\"[00] WARN: bincode::serialize(&receipt) failed\");\n"
    "    }\n"
    "    println!(\"[00] receipt verified successfully against MULTIPLY_ID (real STARK seal)\");\n"
    "    // --- end patch ---\n"
)
main_re = re.compile(r"fn\s+main\s*\(\s*\)\s*\{")
fm = main_re.search(src)
if not fm:
    sys.exit("no fn main() in host/src/main.rs; refusing to patch")
# Walk to the matching closing brace of main().
depth = 0
i = fm.end() - 1
while i < len(src):
    c = src[i]
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            break
    i += 1
src = src[:i] + patch + src[i:]
p.write_text(src)
print(f"patched {p}")
PY
    fi

    # Some cargo-risczero versions don't list `bincode` in host/Cargo.toml; add
    # it if missing so the patch above compiles.
    HOST_TOML="${PROJ}/host/Cargo.toml"
    if [[ -f "${HOST_TOML}" ]] && ! grep -qE '^bincode\s*=' "${HOST_TOML}"; then
        echo "    -> adding bincode dep to host/Cargo.toml"
        python3 - "${HOST_TOML}" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if "[dependencies]" not in src:
    src += "\n[dependencies]\n"
src = src.replace(
    "[dependencies]",
    "[dependencies]\nbincode = \"1.3\"",
    1,
)
p.write_text(src)
PY
    fi
else
    echo "    [skip] reusing existing project at ${PROJ}"
fi

cd "${PROJ}"

LOG="${ART}/risc0-hello-world.log"
echo "    -> cargo run --release (this is the real prove+verify; first run can take 30-120 s)"
# Pipe stdout AND stderr into the artefact log AND the live console so the
# recording sees what's happening. We deliberately let `set -o pipefail`
# bubble up cargo's exit code.
cargo run --release 2>&1 | tee "${LOG}"

if ! grep -qiE 'verif|receipt is valid|success' "${LOG}"; then
    echo "ERROR: cargo run finished but no verifier-success line found in ${LOG}" >&2
    echo "       Tail of log:" >&2
    tail -n 30 "${LOG}" >&2
    exit 5
fi

RECEIPT="${ART}/risc0-hello-world.receipt.bin"
if [[ -f "${RECEIPT}" ]]; then
    sz=$(stat -c '%s' "${RECEIPT}" 2>/dev/null || stat -f '%z' "${RECEIPT}")
    echo "    -> ${RECEIPT} (${sz} bytes)"
else
    echo "WARN: ${RECEIPT} not produced; the template may not have run our patched serialiser." >&2
    echo "      The verifier-success line above still proves prove+verify ran." >&2
fi

echo "==> [00] OK (REAL crypto)"
