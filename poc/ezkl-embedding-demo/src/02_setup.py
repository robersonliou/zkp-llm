#!/usr/bin/env python3
"""02_setup.py — EZKL settings + calibration + compile + SRS + setup.

Pipeline (mirrors docs.ezkl.xyz/getting_started/getting-started):
  gen_settings        -> settings.json
  calibrate_settings  -> updates settings.json with resource-aware quant
  compile_circuit     -> model.compiled
  get_srs             -> fetches/builds the structured reference string
  setup               -> pk.key + vk.key

EZKL 22.x exposes several bindings (notably ``get_srs`` and ``setup``) as
pyo3-asyncio futures that require a *running* asyncio loop just to be
invoked — calling them outside one raises ``RuntimeError: no running event
loop`` before any awaitable is ever returned.  The bindings hand back
``asyncio.Future`` instances (not coroutines), so we must check
``inspect.isawaitable`` rather than ``iscoroutine``.  We therefore drive the
whole pipeline from ``asyncio.run(amain())`` and use ``_maybe_await`` to
transparently await any binding that returns an awaitable while still
handling the synchronous bindings (``gen_settings``, ``calibrate_settings``,
``compile_circuit``) without changes.

SRS fetch: ezkl 22.x's hardcoded primary mirror
``trusted-setup-halo2kzg.s3.eu-central-1.amazonaws.com`` has been returning
``403 AccessDenied`` since 2026-05 (the bucket policy was tightened).  When
``ezkl.get_srs`` fails we transparently fall back to the Scroll mirror
(``circuit-release.s3.us-west-2.amazonaws.com/setup/params{k}``) which hosts
the same Hermez/PSE PoT files in halo2 raw format — verified byte-compatible
with ezkl 22.3.0's ``setup()`` for the logrows we use (k = 15).
"""
from __future__ import annotations

import asyncio
import inspect
import json
import os
import sys
import urllib.request
from pathlib import Path

import ezkl


async def _maybe_await(result):
    """Await ``result`` if it is awaitable (coroutine or Future), else pass through."""
    if inspect.isawaitable(result):
        return await result
    return result

ARTEFACTS = Path(__file__).resolve().parent.parent / "artefacts"
MODEL_ONNX = ARTEFACTS / "model.onnx"
INPUT_JSON = ARTEFACTS / "input.json"
SETTINGS = ARTEFACTS / "settings.json"
COMPILED = ARTEFACTS / "model.compiled"
PK = ARTEFACTS / "pk.key"
VK = ARTEFACTS / "vk.key"

SRS_FALLBACK_TEMPLATE = (
    "https://circuit-release.s3.us-west-2.amazonaws.com/setup/params{logrows}"
)


def _require(path: Path, hint: str) -> None:
    if not path.exists():
        print(f"ERROR: required file missing: {path}", file=sys.stderr)
        print(f"       {hint}", file=sys.stderr)
        sys.exit(2)


def _srs_dir() -> Path:
    return Path(os.environ.get("EZKL_SRS_PATH", os.path.expanduser("~/.ezkl/srs")))


def _logrows_from_settings(settings_path: Path) -> int:
    return int(json.loads(settings_path.read_text())["run_args"]["logrows"])


def _fallback_fetch_srs(logrows: int) -> Path:
    target_dir = _srs_dir()
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"kzg{logrows}.srs"
    if target.exists() and target.stat().st_size > 0:
        print(f"[02/4-fallback] SRS already cached at {target} ({target.stat().st_size:,} bytes)")
        return target
    url = SRS_FALLBACK_TEMPLATE.format(logrows=logrows)
    print(f"[02/4-fallback] fetching SRS from Scroll mirror: {url}")
    urllib.request.urlretrieve(url, target.as_posix())
    print(f"[02/4-fallback] wrote {target} ({target.stat().st_size:,} bytes)")
    return target


async def _ensure_srs(settings_path: Path) -> None:
    """Try ezkl's primary mirror first; on failure, fall back to Scroll mirror."""
    try:
        await _maybe_await(ezkl.get_srs(settings_path=settings_path.as_posix()))
        return
    except Exception as exc:
        print(f"[02/4] primary ezkl.get_srs mirror failed ({exc.__class__.__name__}: {exc})")
    logrows = _logrows_from_settings(settings_path)
    _fallback_fetch_srs(logrows)


async def amain() -> None:
    _require(MODEL_ONNX, "Run 01_make_model.py first.")
    _require(INPUT_JSON, "Run 01_make_model.py first.")

    print(f"[02/1] gen_settings -> {SETTINGS}")
    py_run_args = ezkl.PyRunArgs()
    py_run_args.input_visibility = "public"
    py_run_args.output_visibility = "public"
    py_run_args.param_visibility = "fixed"

    ok = await _maybe_await(ezkl.gen_settings(
        model=MODEL_ONNX.as_posix(),
        output=SETTINGS.as_posix(),
        py_run_args=py_run_args,
    ))
    if ok is False:
        raise RuntimeError("ezkl.gen_settings returned False")

    print(f"[02/2] calibrate_settings target=resources")
    await _maybe_await(ezkl.calibrate_settings(
        data=INPUT_JSON.as_posix(),
        model=MODEL_ONNX.as_posix(),
        settings=SETTINGS.as_posix(),
        target="resources",
        scales=[2, 7],
        max_logrows=17,
    ))

    print(f"[02/3] compile_circuit -> {COMPILED}")
    ok = await _maybe_await(ezkl.compile_circuit(
        model=MODEL_ONNX.as_posix(),
        compiled_circuit=COMPILED.as_posix(),
        settings_path=SETTINGS.as_posix(),
    ))
    if ok is False:
        raise RuntimeError("ezkl.compile_circuit returned False")

    print(f"[02/4] get_srs (this can take 1-2 min on first run)")
    await _ensure_srs(SETTINGS)

    print(f"[02/5] setup -> {PK}, {VK}")
    ok = await _maybe_await(ezkl.setup(
        model=COMPILED.as_posix(),
        vk_path=VK.as_posix(),
        pk_path=PK.as_posix(),
    ))
    if ok is False:
        raise RuntimeError("ezkl.setup returned False")

    print("[02] OK")


def main() -> None:
    asyncio.run(amain())


if __name__ == "__main__":
    main()
