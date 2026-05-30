# `poc/` — ZKP PoC Mono-Repo

Two minimal, reproducible zero-knowledge-proof demos. Each is self-contained
and runs in Docker; see the per-demo `README.md` for details. (The full
project overview is in `../README.md`.)

| Demo | What it shows | Core stack | Walltime |
|------|---------------|-----------|----------|
| **A. EZKL Embedding** (`ezkl-embedding-demo/`) | zkRAG / zkLLM "verifiable embedding step": 384→64 linear layer → ONNX → Halo2 prove/verify | EZKL 22.x (Halo2) | ~3 min |
| **B. RISC0 × Cartesi Step Proof** (`risc0-cartesi-step-demo/`) | Proof of one Cartesi v0.20.0 machine step via the RISC0 zkVM | RISC0 zkVM 2.x + cartesi-machine v0.20.0 | mock ~55 s / dev ~77 s (after build) |

The two demos are fully independent — build and run them separately.

## Prerequisites

- Docker ≥ 24 with a reachable daemon
- Disk: ~10 GB minimum, ~20 GB recommended (Demo B's toolchain image is ~8 GB)
- RAM: 8 GB covers both default paths; Demo B `--full` needs ≥16 GB
- Network: required on first build/run (base images, EZKL SRS, Cartesi release assets)
- Demo B's first `docker build` is heavy (~18 min; pulls rustup + cargo-risczero ~2 GB) — build it ahead of time.

## Run Demo A — EZKL

```bash
cd poc/ezkl-embedding-demo
docker build -t ezkl-embedding-demo .
mkdir -p artefacts
docker run --rm -v "$(pwd)/artefacts:/work/artefacts" ezkl-embedding-demo   # -> PROOF VERIFIED
```

## Run Demo B — RISC0 × Cartesi

```bash
cd poc/risc0-cartesi-step-demo
docker build -t risc0-cartesi-demo:local .
# mock (~55s):
docker run --rm -v "$(pwd)/artefacts:/work/artefacts" -v "$(pwd)/dist:/work/dist" \
  risc0-cartesi-demo:local bash scripts/run-all.sh --mock-mode
# dev-real (~77s): same command with --dev-mode
```

Expected success strings: Demo A → `PROOF VERIFIED`; Demo B mock →
`[MOCK] step.proof.bin verified: ...`; Demo B dev → `✅ Receipt is valid!` +
`[DEV-REAL] step.proof.bin verified: ...`.

## Directory structure

```
poc/
├── README.md                         # this file
├── ezkl-embedding-demo/
│   ├── README.md
│   ├── Dockerfile                    # python:3.11-slim-bookworm
│   ├── requirements.txt              # ezkl + torch (CPU) + onnx + jupyter
│   ├── src/                          # 01_make_model → 02_setup → 03_prove → 04_verify (+ notebook.ipynb)
│   └── scripts/                      # run-all.sh (default entrypoint) + clean.sh
└── risc0-cartesi-step-demo/
    ├── README.md
    ├── Dockerfile                    # debian:trixie-slim (multi-stage)
    ├── docker-compose.yml
    ├── scripts/                      # run-all.sh + 00–05 stage scripts
    ├── cartesi-machine/              # "counter" workload crate (illustrative; not built by the pipeline)
    └── solidity/                     # IRiscZeroVerifier wrapper reference (illustrative; not compiled/called)
```

## Notes

- Run the default/mock path first to confirm everything is green before attempting heavier modes.
- EZKL downloads a KZG SRS (~1.5 GB) on first run, then caches it.
- `artefacts/` (outputs) and `dist/` (cached downloads) are populated at run time.
