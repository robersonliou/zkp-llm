# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# Demo B: Cartesi machine state-transition proof via RISC0 zkVM
#
# Base: debian:trixie-slim because Cartesi Machine Emulator v0.20.0 release
#   notes confirm the upstream image bumped Bookworm -> Trixie (Debian 13).
#   The machine-emulator_*.deb is built against Trixie's libstdc++/libgomp.
#
# Stages:
#   builder   : installs RISC0 toolchain + cargo-risczero (heavy, ~2 GB)
#   runtime   : copies the prover bin, the .deb, and shell scripts; small
#
# Build:  docker build -t risc0-cartesi-demo:local .
# Run:    docker run --rm -v "$(pwd)/artefacts:/work/artefacts" \
#             -v "$(pwd)/dist:/work/dist" \
#             risc0-cartesi-demo:local bash scripts/run-all.sh --mock-mode
# ---------------------------------------------------------------------------

############################
# Stage 1: builder (heavy) #
############################
FROM debian:trixie-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libssl-dev \
        libtbb-dev \
        pkg-config \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install rustup + stable toolchain (we need stable 1.81+ for cargo-risczero 2.x).
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | bash -s -- -y --default-toolchain 1.83.0 --profile minimal --no-modify-path

# Pin cargo-risczero. 2.3.2 is the conservative-stable choice (see
# https://github.com/risc0/risc0/releases). cargo-risczero ships `r0vm` and
# is what `cargo risczero new` / `cargo risczero verify` dispatch to.
RUN cargo install cargo-risczero --version 2.3.2 --locked

# Install rzup (the RISC0 version manager) and use it to fetch the riscv32im
# zkVM Rust toolchain (~250 MB). rzup hard-codes its install dir to
# $HOME/.risc0 — we set HOME=/opt/rzhome so the resulting tree is easy to
# copy across the multi-stage build. `rzup install rust` registers a custom
# rustup toolchain named `risc0` under /opt/rustup/toolchains/risc0, which is
# what the cargo-risczero template's `methods` crate uses to build guests.
ENV HOME=/opt/rzhome
RUN set -eux; \
    mkdir -p /opt/rzhome; \
    curl -L https://risczero.com/install -o /tmp/rzup-install.sh; \
    bash /tmp/rzup-install.sh; \
    rm -f /tmp/rzup-install.sh
ENV PATH=/opt/rzhome/.risc0/bin:/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin
RUN rzup install rust
# Sanity check: cargo-risczero needs to find the risc0 rustup toolchain.
RUN rustup toolchain list && ls /opt/rustup/toolchains/

############################
# Stage 2: runtime (slim)  #
############################
FROM debian:trixie-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin

# Runtime deps: machine-emulator's .deb pulls libstdc++, libtbb12, libssl3, etc.
# We pre-install what we know we need so the .deb install can finish offline.
# gcc-riscv64-linux-gnu + binutils-riscv64-linux-gnu (~200 MB) are added for the
# `--dev-mode` path so anyone wanting to cross-compile a RV64 guest can do so;
# they are NOT required by the minimal dev-mode pipeline we ship (which uses
# `cartesi-machine --no-ram-image --no-root-flash-drive`), but they unlock the
# upgrade path documented in the v0.20.0 release notes.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils-riscv64-linux-gnu \
        build-essential \
        ca-certificates \
        curl \
        file \
        gcc-riscv64-linux-gnu \
        jq \
        libgomp1 \
        libssl3 \
        libtbb12 \
        openssl \
        pkg-config \
        python3 \
        xxd \
    && rm -rf /var/lib/apt/lists/*

# Pull the toolchain over from builder. The rustup + rzup install is large
# (~2 GB) — students can pass `--target=builder` to docker build if they want
# to skip this for a fast mock-only build.
COPY --from=builder /opt/cargo   /opt/cargo
COPY --from=builder /opt/rustup  /opt/rustup
COPY --from=builder /opt/rzhome  /opt/rzhome
ENV HOME=/opt/rzhome \
    PATH=/opt/rzhome/.risc0/bin:/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin

WORKDIR /work

# Bring in the source tree.
COPY cartesi-machine/ /work/cartesi-machine/
COPY scripts/         /work/scripts/
COPY solidity/        /work/solidity/

RUN mkdir -p /work/artefacts /work/dist \
    && chmod +x /work/scripts/*.sh

# Pre-warm the RISC0 hello-world project: scaffold it, patch host/src/main.rs,
# and run a full real prove+verify ONCE during build. This caches the cargo
# target/ tree and the rustup risc0 toolchain assets in the image so that the
# first `docker run scripts/run-all.sh` only pays for a single ~30 s prove
# pass instead of a full ~5 min compile-from-scratch. The build-time receipt
# in /work/artefacts is overlaid by the user's host mount at runtime, so each
# recording session still produces its own fresh receipt.
RUN bash /work/scripts/00-risc0-hello-world.sh

# Default to hybrid mode (00,01 real; 02-05 mock) — see scripts/run-all.sh.
CMD ["bash", "/work/scripts/run-all.sh", "--mock-mode"]
