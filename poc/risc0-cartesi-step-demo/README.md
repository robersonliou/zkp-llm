# Demo B — Cartesi Machine Step Proof via RISC0 zkVM

Run a single Cartesi machine step (collecting the pre/post state root hashes)
inside one Docker container, then use the RISC0 zkVM to produce and verify a
proof of that step. Stage 00 first runs a **real** RISC0 prove + verify as
end-to-end evidence that the toolchain and cryptography work; stages 02–05 run
in either mock (shape-only) or dev-real (real cartesi-machine + RISC0 dev
receipt) mode depending on the flag.

Aligned with the Cartesi machine-emulator v0.20.0 release (the first to
natively support the RISC0 zkVM).

## Prerequisites

- Docker ≥ 24 (daemon must be reachable)
- Disk ~10 GB (image ~8 GB)
- RAM: ~1 GB for mock mode, ~2 GB for dev mode
- First build / run needs network: the build pulls rustup + cargo-risczero
  (~2 GB); stage 01 fetches the prover bin and `.deb` from the GitHub release.
  After one successful run it can be re-run offline.

## 1. Build the image

```bash
cd poc/risc0-cartesi-step-demo
docker build -t risc0-cartesi-demo:local .   # first build ~18 min
```

## 2. Run — mock mode (default, ~55 s measured)

Stages 00/01 are real cryptography and a real download; stages 02–05 are
shape-only mock — the lightest path.

```bash
mkdir -p artefacts dist
docker run --rm \
  -v "$(pwd)/artefacts:/work/artefacts" \
  -v "$(pwd)/dist:/work/dist" \
  risc0-cartesi-demo:local \
  bash scripts/run-all.sh --mock-mode
```

Expected success output (both lines must appear to pass):

```
[00] receipt verified successfully against MULTIPLY_ID (real STARK seal)
[MOCK] step.proof.bin verified: pre_root↔post_root match, mcycle_count=100
```

## 3. Run — dev-real mode (~77 s measured)

Stages 02–05 switch to a real cartesi-machine snapshot + `RISC0_DEV_MODE=1`
r0vm (a dev receipt — not a real STARK seal, but it exercises the full
guest + host loop).

```bash
docker run --rm \
  -v "$(pwd)/artefacts:/work/artefacts" \
  -v "$(pwd)/dist:/work/dist" \
  risc0-cartesi-demo:local \
  bash scripts/run-all.sh --dev-mode
```

Expected success output:

```
✅ Receipt is valid!
[DEV-REAL] step.proof.bin verified: pre_root↔post_root match, mcycle=1, dev-receipt=true
```

> `--full` (a real STARK seal) needs ≥16 GB RAM; it is currently a stub and out of scope for this PoC.

## Directory layout

```
risc0-cartesi-step-demo/
├── Dockerfile            # debian:trixie-slim multi-stage; installs rustup + cargo-risczero 2.3.2 + rzup
├── scripts/
│   ├── run-all.sh        # entrypoint driver (--mock-mode / --dev-mode / --full)
│   ├── 00-risc0-hello-world.sh  # real RISC0 prove + verify (runs in every mode)
│   ├── 01-fetch-prover-bin.sh   # fetch the v0.20.0 release prover bin + .deb
│   ├── 02-build-machine.sh      # dev: build a minimal cartesi-machine snapshot (sha256 hash tree)
│   ├── 03-collect-step.sh       # dev: --log-step collects step.bin + pre/post root
│   ├── 04-prove.sh              # dev: r0vm produces the receipt
│   └── 05-verify.sh             # dev: cargo risczero verify
├── cartesi-machine/      # early "counter" workload crate; NOT compiled by the current pipeline (illustrative only)
├── solidity/             # on-chain verifier reference (vendored from risc0-ethereum; illustrative only, never compiled/called by the pipeline)
└── artefacts/, dist/     # generated at run time (artefacts = outputs; dist = cached downloads)
```
