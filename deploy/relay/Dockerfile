# syntax=docker/dockerfile:1
# sepot-relay — multi-stage build (kontext = kořen monorepa, viz compose)
#
# Build stage potřebuje: protoc (prost-build generuje z proto/sepot.proto),
# git (libsignal-protocol je git dependency s [patch.crates-io] zrcadlem).

FROM rust:1.99-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      protobuf-compiler git pkg-config build-essential cmake \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY proto/ proto/
COPY rust/ rust/
WORKDIR /src/rust
# Cache mounty: rebuild po změně zdrojáků nekompiluje závislosti znovu.
# Binárka se musí zkopírovat VEN z cache mountu (po RUN kroku zmizí).
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/rust/target \
    cargo build --release -p sepot-relay \
    && cp target/release/sepot-relay /sepot-relay

FROM debian:bookworm-slim
# Revize zdroje: label pro `docker inspect` a env pro /v1/server-info
# (AGPL §13 — uživatel relaye má vědět, který commit běží).
ARG GIT_SHA=dev
LABEL org.opencontainers.image.revision=$GIT_SHA \
      org.opencontainers.image.source="https://github.com/juliusjoska/sepot"
ENV SEPOT_REVISION=$GIT_SHA
# upgrade: základ bookworm-slim nese opravitelné CVE v perl-base a spol.;
# bez něj by každý build vozil zranitelnosti, které Debian už opravil.
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /usr/sbin/nologin sepot \
    # předvytvořit s právy sepot — named volume zdědí ownership z image
    && mkdir -p /var/lib/sepot/attachments \
    && chown -R sepot /var/lib/sepot
COPY --from=build /sepot-relay /usr/local/bin/sepot-relay
USER sepot
EXPOSE 8470
# Migrace (sqlx::migrate!) jsou zakompilované v binárce, běží při startu
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD curl -fsS http://127.0.0.1:8470/v1/health || exit 1
CMD ["sepot-relay"]
