#!/usr/bin/env python3
"""01_make_model.py — Tiny embedding model + sample input for EZKL.

Goal: emulate ONE projection layer from a sentence-transformer style encoder
(e.g. all-MiniLM-L6-v2 maps 384-dim hidden -> some downstream space).  We use
a 384 -> 64 Linear + bias to keep the circuit small enough that proving on a
laptop CPU finishes in <30 s with EZKL 22.x.

Outputs (under ./artefacts/):
  - model.onnx        : 384 -> 64 linear, opset 11
  - input.json        : EZKL-format witness input (shape [1, 384] flattened)

EZKL plays nicest with ONNX opset 11-13; we pin opset 11.
This script is idempotent: re-running overwrites the same files.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

ARTEFACTS = Path(__file__).resolve().parent.parent / "artefacts"
ARTEFACTS.mkdir(parents=True, exist_ok=True)

MODEL_PATH = ARTEFACTS / "model.onnx"
INPUT_PATH = ARTEFACTS / "input.json"

IN_DIM = 384
OUT_DIM = 64
SEED = 42


class TinyEmbedding(nn.Module):
    """Single linear projection ~ one layer of a sentence-transformer head."""

    def __init__(self, in_dim: int = IN_DIM, out_dim: int = OUT_DIM) -> None:
        super().__init__()
        self.proj = nn.Linear(in_dim, out_dim, bias=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.proj(x)


def main() -> None:
    torch.manual_seed(SEED)
    np.random.seed(SEED)

    model = TinyEmbedding().eval()
    # Initialise weights small so quantisation calibration converges quickly.
    with torch.no_grad():
        nn.init.normal_(model.proj.weight, mean=0.0, std=0.05)
        nn.init.zeros_(model.proj.bias)

    # Sample input mimicking a normalised hidden vector.
    sample = torch.randn(1, IN_DIM, dtype=torch.float32) * 0.1

    print(f"[01] Exporting ONNX to {MODEL_PATH} (opset 11)...")
    torch.onnx.export(
        model,
        sample,
        MODEL_PATH.as_posix(),
        export_params=True,
        opset_version=11,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["embedding"],
        dynamic_axes=None,
    )

    # EZKL input format: {"input_data": [[...flat float list...]]}
    flat = sample.flatten().tolist()
    payload = {"input_data": [flat]}
    INPUT_PATH.write_text(json.dumps(payload))
    print(f"[01] Wrote witness input to {INPUT_PATH} ({len(flat)} values).")

    # Quick reference forward — pure torch, just to log a canonical output.
    with torch.no_grad():
        ref_out = model(sample).flatten().tolist()
    print(f"[01] Reference output (first 5 dims): {ref_out[:5]}")
    print("[01] OK")


if __name__ == "__main__":
    main()
