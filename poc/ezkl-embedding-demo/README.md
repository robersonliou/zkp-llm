# Demo A — Verifiable Embedding Step (EZKL)

A minimal **verifiable-embedding** unit for zkRAG / zkLLM: a `384 -> 64` linear
projection is exported to ONNX, compiled into a Halo2 circuit with EZKL, then
proven and verified. A successful run prints `PROOF VERIFIED` and produces an
on-chain-verifiable `proof.json` + `vk.key`.

## Prerequisites

- **Docker** (recommended — avoids native EZKL build issues on WSL/macOS).
- **~3 GB** free disk, mostly for the KZG SRS (public parameters).

## Run (Docker)

```bash
cd poc/ezkl-embedding-demo
docker build -t ezkl-embedding-demo .
mkdir -p artefacts
docker run --rm -v "$(pwd)/artefacts:/work/artefacts" ezkl-embedding-demo
```

The container's default `CMD` runs `scripts/run-all.sh`, which executes stages
`01 -> 02 -> 03 -> 04` and ends with the success line:

```
PROOF VERIFIED
```

## Verify after a run

After `scripts/run-all.sh` has generated `artefacts/proof.json`,
`artefacts/vk.key`, and `artefacts/settings.json`, you can re-check the proof
without re-running setup/prove:

```bash
python src/04_verify.py   # -> PROOF VERIFIED
```

## Bare-metal alternative (no Docker)

```bash
cd poc/ezkl-embedding-demo
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
./scripts/run-all.sh
```

## Layout

```
src/
  01_make_model.py   # PyTorch 384->64 linear -> model.onnx + input.json
  02_setup.py        # gen_settings -> calibrate -> compile -> fetch SRS -> setup (pk/vk)
  03_prove.py        # gen_witness -> proof.json
  04_verify.py       # ezkl.verify -> prints PROOF VERIFIED
scripts/run-all.sh   # runs stages 01..04 end-to-end (container entrypoint)
```

All outputs land in `artefacts/`, which is generated at run time and ignored by
Git. The verifier needs only `proof.json`, `vk.key`, and `settings.json`;
`proof.json` + `vk.key` are what an on-chain (Solidity / Halo2) verifier checks.

## References

- EZKL docs: <https://docs.ezkl.xyz/>
- zkLLM: <https://arxiv.org/abs/2404.16109>
