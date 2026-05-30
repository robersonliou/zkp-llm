#!/usr/bin/env python3
"""03_prove.py — Witness generation + proof for the tiny embedding.

Pipeline:
  gen_witness  -> witness.json
  prove        -> proof.json

We use the "single" proof type (default) which is the simplest non-aggregated
Halo2 proof. Plenty for a 384->64 linear projection.

EZKL 22.x's pyo3-asyncio bindings (``gen_witness``, ``prove``) require a
running asyncio loop to be invoked and return ``asyncio.Future`` instances
(not coroutines), so we drive the whole script from ``asyncio.run(amain())``
and use ``_maybe_await`` to transparently await any binding that hands back
an awaitable.
"""
from __future__ import annotations

import asyncio
import inspect
import sys
from pathlib import Path

import ezkl


async def _maybe_await(result):
    """Await ``result`` if it is awaitable (coroutine or Future), else pass through."""
    if inspect.isawaitable(result):
        return await result
    return result

ARTEFACTS = Path(__file__).resolve().parent.parent / "artefacts"
INPUT_JSON = ARTEFACTS / "input.json"
COMPILED = ARTEFACTS / "model.compiled"
PK = ARTEFACTS / "pk.key"
WITNESS = ARTEFACTS / "witness.json"
PROOF = ARTEFACTS / "proof.json"


def _require(path: Path, hint: str) -> None:
    if not path.exists():
        print(f"ERROR: required file missing: {path}", file=sys.stderr)
        print(f"       {hint}", file=sys.stderr)
        sys.exit(2)


async def amain() -> None:
    _require(INPUT_JSON, "Run 01_make_model.py first.")
    _require(COMPILED, "Run 02_setup.py first.")
    _require(PK, "Run 02_setup.py first.")

    print(f"[03/1] gen_witness -> {WITNESS}")
    await _maybe_await(ezkl.gen_witness(
        data=INPUT_JSON.as_posix(),
        model=COMPILED.as_posix(),
        output=WITNESS.as_posix(),
    ))

    print(f"[03/2] prove -> {PROOF} (this is the slow step; ~5-30 s)")
    await _maybe_await(ezkl.prove(
        witness=WITNESS.as_posix(),
        model=COMPILED.as_posix(),
        pk_path=PK.as_posix(),
        proof_path=PROOF.as_posix(),
        proof_type="single",
    ))

    proof_size = PROOF.stat().st_size
    print(f"[03] OK. Proof size = {proof_size:,} bytes.")


def main() -> None:
    asyncio.run(amain())


if __name__ == "__main__":
    main()
