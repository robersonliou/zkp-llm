# Demo B — Cartesi Machine Step Proof (RISC0 × Cartesi) — Run Results

**Date:** 2026-06-05  
**Status:** VERIFIED ✅ (mock-mode + dev-mode)

---

## Environment

| Item | Value |
|------|-------|
| Docker image | `risc0-cartesi-demo:local` |
| Base image | `debian:trixie-slim` (multi-stage) |
| Rust toolchain | 1.83.0 |
| cargo-risczero | 2.3.2 |
| Cartesi machine emulator | v0.20.0 (`machine-emulator_amd64.deb`) |
| Prover image ID | `3aec8c717d9b47f9b617c1695955d75e2bb525085283c1076591f97ae643c990` |

---

## Modes

| Mode | Description | STARK seal? |
|------|-------------|-------------|
| `--mock-mode` | Stages 00–01 real crypto; 02–05 shape-only mock | No (magic header) |
| `--dev-mode` | Stages 00–05 all real (RISC0_DEV_MODE=1) | No (dev receipt) |
| `--full` | Full STARK proof | Stub / out of scope |

---

## Pipeline Stages

### `--mock-mode` ✅

| Stage | Description | Status |
|-------|-------------|--------|
| [00] | RISC0 hello-world compile + real prove + verify (STARK seal) | ✅ OK |
| [01] | Download Cartesi v0.20.0 release assets | ✅ OK |
| [02] | Write stub machine-snapshot (README + config.json) | ✅ OK (MOCK) |
| [03] | Emit 5 dense uarch hashes + JSON skeleton | ✅ OK (MOCK) |
| [04] | Write 264-byte `MOCKPRF`-magic proof | ✅ OK (MOCK) |
| [05] | Verify mock header: pre_root↔post_root match | ✅ **VERIFIED** |

Key outputs:
```
[00] receipt verified successfully against MULTIPLY_ID (real STARK seal)
[MOCK] step.proof.bin verified: pre_root↔post_root match, mcycle_count=100
```

### `--dev-mode` ✅

| Stage | Description | Status |
|-------|-------------|--------|
| [00] | RISC0 hello-world compile + real prove + verify (STARK seal) | ✅ OK |
| [01] | Assets skipped (cached from mock run) | ✅ OK |
| [02] | Real Cartesi machine snapshot (sha256 hash tree, 144 MB) | ✅ OK |
| [03] | Real `cartesi-machine --log-step`, binary v0.20.0 step log | ✅ OK |
| [04] | `RISC0_DEV_MODE=1` r0vm prove → dev receipt (no STARK seal) | ✅ OK |
| [05] | `cargo risczero verify` → dev receipt valid | ✅ **VERIFIED** |

Key outputs:
```
✅ Receipt is valid!
[DEV-REAL] step.proof.bin verified: pre_root↔post_root match, mcycle=1, dev-receipt=true
```

---

## Step Transition (dev-mode)

| Field | Value |
|-------|-------|
| pre_root | `0xde22660f0b61cae65731ba5bc3e5707dceccc2c5e5d4902768c7645ca4d48104` |
| post_root | `0x3b64f9b917a9d9eac7329929aa5b2d02471d4c30c2a1b6a131b68c59344f50fe` |
| mcycle_count | 1 |
| step.bin | 18,944 bytes |

---

## Output Artefacts

### mock-mode

| File | Size | Description |
|------|------|-------------|
| `risc0-hello-world.receipt.bin` | 205 KB | RISC0 hello-world real STARK receipt |
| `machine-snapshot/` | stub | Mock snapshot directory |
| `step.log.json` | 844 B | Mock step log |
| `step.pre.hash` / `step.post.hash` | 67 B each | Pre/post root hashes |
| `step.proof.bin` | 264 B | Mock proof (MOCKPRF magic header) |
| `step.public.json` | 377 B | Public inputs JSON |

### dev-mode

| File | Size | Description |
|------|------|-------------|
| `risc0-hello-world.receipt.bin` | 205 KB | RISC0 hello-world real STARK receipt |
| `machine-snapshot/` | 144 MB | Real Cartesi machine snapshot (hash tree) |
| `step.bin` | 19 KB | Real binary step log (v0.20.0 format) |
| `step.log.json` | 556 B | Step metadata JSON |
| `step.uarch-hashes.txt` | 136 B | 2 dense uarch hashes |
| `step.pre.hash` / `step.post.hash` | 67 B each | Pre/post root hashes |
| `step.proof.bin` | 393 B | Dev receipt (NOT a real STARK seal) |
| `step.public.json` | 456 B | Public inputs JSON |

---

## Commands Used

```bash
cd poc/risc0-cartesi-step-demo
docker build -t risc0-cartesi-demo:local .

# mock-mode
mkdir -p artefacts dist
docker run --rm \
  -v "$(pwd)/artefacts:/work/artefacts" \
  -v "$(pwd)/dist:/work/dist" \
  risc0-cartesi-demo:local bash scripts/run-all.sh --mock-mode

# dev-mode
docker run --rm \
  -v "$(pwd)/artefacts:/work/artefacts" \
  -v "$(pwd)/dist:/work/dist" \
  risc0-cartesi-demo:local bash scripts/run-all.sh --dev-mode
```

---

## Notes

- Docker image build took ~28 minutes (dominated by `cargo install cargo-risczero` at ~19 min).
- Dev receipt is **not a real STARK proof** — `RISC0_DEV_MODE=1` skips witness generation. Use `--full` for a production-grade seal (requires ≥16 GB RAM).
- `step.proof.bin` + `step.public.json` are the inputs to the on-chain `StepVerifier.sol`.
