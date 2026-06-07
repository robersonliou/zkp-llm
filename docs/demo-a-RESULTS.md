# Demo A — Verifiable Embedding Step (EZKL) — Run Results

**Date:** 2026-06-05  
**Status:** PROOF VERIFIED ✅

---

## Environment

| Item | Value |
|------|-------|
| Docker image | `ezkl-embedding-demo` |
| Base image | `python:3.11-slim-bookworm` |
| EZKL version | 22.3.0 |
| Commitment scheme | KZG (Halo2) |

---

## Model

| Parameter | Value |
|-----------|-------|
| Architecture | Linear projection (fully connected) |
| Input dimension | 384 |
| Output dimension | 64 |
| Format | ONNX (opset 11) |
| File | `artefacts/model.onnx` (97 KB) |

Reference output (first 5 dims):
```
[-0.025267943739891052, -0.03612520173192024, 0.08039101213216782,
  0.05907692015171051,  0.059878282248973846]
```

---

## Circuit (EZKL settings)

| Parameter | Value |
|-----------|-------|
| input_scale | 7 |
| param_scale | 7 |
| scale_rebase_multiplier | 10 |
| logrows | 15 |
| num_rows | 14,880 |
| total_assignments | 29,760 |
| input_visibility | Public |
| output_visibility | Public |
| param_visibility | Fixed |
| SRS file | `kzg15.srs` (4,194,564 bytes) |

---

## Numerical Fidelity Report

| Metric | Value |
|--------|-------|
| mean_error | 0.00037927736 |
| median_error | 0.0011398345 |
| max_error | 0.011209503 |
| min_error | -0.011190176 |
| mean_abs_error | 0.004396946 |
| max_abs_error | 0.011209503 |
| mean_squared_error | 0.000028743216 |
| mean_percent_error | -0.14859547 % |
| mean_abs_percent_error | 0.2885674 % |

---

## Pipeline Stages

| Stage | Description | Status |
|-------|-------------|--------|
| [01] | PyTorch 384→64 Linear → `model.onnx` + `input.json` | ✅ OK |
| [02] | gen_settings → calibrate → compile → fetch SRS → setup (pk/vk) | ✅ OK |
| [03] | gen_witness → prove → `proof.json` | ✅ OK |
| [04] | verify proof | ✅ **PROOF VERIFIED** |

---

## Output Artefacts

| File | Size | Description |
|------|------|-------------|
| `model.onnx` | 97 KB | ONNX model |
| `model.compiled` | 782 KB | Compiled Halo2 circuit |
| `input.json` | 8.2 KB | Public input (384 values) |
| `witness.json` | 66 KB | ZK witness |
| `proof.json` | 82 KB | ZK proof (83,767 bytes) |
| `vk.key` | 66 KB | Verification key (on-chain verifier input) |
| `pk.key` | 133 MB | Proving key |
| `settings.json` | 1.3 KB | Circuit settings |

> `proof.json` + `vk.key` are what an on-chain (Solidity / Halo2) verifier checks.

---

## Commands Used

```bash
cd poc/ezkl-embedding-demo
docker build -t ezkl-embedding-demo .
mkdir -p artefacts
docker run --rm -v "$(pwd)/artefacts:/work/artefacts" ezkl-embedding-demo
```

---

## Notes

- Primary EZKL SRS mirror failed; fell back to Scroll mirror successfully.
- `low scale values (<8) may impact precision` warning is expected at scale=7 (resources target).
- Proof size: **83,767 bytes** (~82 KB).
