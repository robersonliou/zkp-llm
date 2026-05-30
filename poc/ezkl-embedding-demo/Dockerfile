# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# Demo A: Verifiable embedding step with EZKL
# Base: python:3.11-slim-bookworm (Debian 12, glibc 2.36 — matches EZKL wheels)
# Build:  docker build -t ezkl-embedding-demo .
# Run:    docker run --rm -v "$(pwd)/artefacts:/work/artefacts" ezkl-embedding-demo
# ---------------------------------------------------------------------------
FROM python:3.11-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System packages: build-essential for any sdist fallback, curl for SRS fetch fallback,
# libgomp1 required at runtime by onnxruntime + torch CPU wheels.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libgomp1 \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Install Python deps first for layer cache.
COPY requirements.txt /work/requirements.txt
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Copy source last so iterating on scripts does not invalidate the deps layer.
COPY src/ /work/src/
COPY scripts/ /work/scripts/

# Pre-create artefacts dir (volume mount usually overlays this).
RUN mkdir -p /work/artefacts \
    && chmod +x /work/scripts/*.sh

# Default entrypoint runs the full pipeline end-to-end.
CMD ["bash", "/work/scripts/run-all.sh"]
