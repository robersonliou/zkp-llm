#!/usr/bin/env python3
"""04_verify.py — Verify the proof.

Standalone: can be run against the committed artefacts (``settings.json`` +
``vk.key`` + ``proof.json``) without first running ``02_setup.py``.  EZKL's
verifier needs the KZG SRS to do the pairing checks, so if it isn't already
cached under ``~/.ezkl/srs/kzg{logrows}.srs`` we transparently fetch it from
the Scroll mirror (PSE's S3 bucket has been returning 403 since 2026-05).

Exit codes:
  0   "PROOF VERIFIED"  (success)
  1   "PROOF REJECTED"  (verifier returned False)
  2   missing prerequisites (run prior scripts first)
  3   exception from ezkl.verify (toolchain / SRS mismatch)
"""
from __future__ import annotations

import json
import os
import sys
import traceback
import urllib.request
from pathlib import Path

import ezkl

ARTEFACTS = Path(__file__).resolve().parent.parent / "artefacts"
SETTINGS = ARTEFACTS / "settings.json"
VK = ARTEFACTS / "vk.key"
PROOF = ARTEFACTS / "proof.json"

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


def _ensure_srs_cached(settings_path: Path) -> None:
    """Fetch SRS from the Scroll mirror if it isn't already cached locally."""
    logrows = int(json.loads(settings_path.read_text())["run_args"]["logrows"])
    target_dir = _srs_dir()
    target = target_dir / f"kzg{logrows}.srs"
    if target.exists() and target.stat().st_size > 0:
        return
    target_dir.mkdir(parents=True, exist_ok=True)
    url = SRS_FALLBACK_TEMPLATE.format(logrows=logrows)
    print(f"[04] SRS not cached; fetching from Scroll mirror: {url}", file=sys.stderr)
    urllib.request.urlretrieve(url, target.as_posix())
    print(f"[04] wrote {target} ({target.stat().st_size:,} bytes)", file=sys.stderr)


def main() -> None:
    _require(SETTINGS, "Run 02_setup.py first.")
    _require(VK, "Run 02_setup.py first.")
    _require(PROOF, "Run 03_prove.py first.")

    _ensure_srs_cached(SETTINGS)

    print(f"[04] verify proof={PROOF}, vk={VK}")
    try:
        ok = ezkl.verify(
            proof_path=PROOF.as_posix(),
            settings_path=SETTINGS.as_posix(),
            vk_path=VK.as_posix(),
        )
    except Exception:
        print("ERROR: ezkl.verify raised an exception:", file=sys.stderr)
        traceback.print_exc()
        sys.exit(3)

    if ok:
        print("PROOF VERIFIED")
        sys.exit(0)
    else:
        print("PROOF REJECTED", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
