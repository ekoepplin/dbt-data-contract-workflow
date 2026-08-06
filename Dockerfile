# syntax=docker/dockerfile:1.6

# ---------------------------------------------------------------------------
# Base — Python 3.11 + uv + DuckDB CLI + git + zsh
# ---------------------------------------------------------------------------
FROM --platform=${TARGETPLATFORM:-linux/amd64} python:3.11-slim-bookworm AS base

ENV UV_SYSTEM_PYTHON=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive

RUN pip install --no-cache-dir uv && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget unzip git zsh make build-essential && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then DUCKDB_ARCH="aarch64"; else DUCKDB_ARCH="amd64"; fi && \
    wget -q https://github.com/duckdb/duckdb/releases/download/v1.1.3/duckdb_cli-linux-${DUCKDB_ARCH}.zip && \
    unzip duckdb_cli-linux-${DUCKDB_ARCH}.zip -d /usr/local/bin && \
    rm duckdb_cli-linux-${DUCKDB_ARCH}.zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Development — interactive devcontainer target
# ---------------------------------------------------------------------------
FROM base AS development
WORKDIR /workspace
COPY pyproject.toml ./
# Warm the dep cache; skip building the local package since /workspace will be
# bind-mounted by the devcontainer at runtime.
RUN uv sync --no-install-project
ENV SHELL=/usr/bin/zsh

# ---------------------------------------------------------------------------
# Production — headless runnable image
# ---------------------------------------------------------------------------
FROM base AS production
WORKDIR /workspace
COPY pyproject.toml Makefile ./
COPY dlt_ingest ./dlt_ingest
COPY dbt_project ./dbt_project
COPY contracts ./contracts
RUN uv sync --no-dev && \
    uv run dbt deps --project-dir dbt_project --profiles-dir dbt_project
CMD ["sleep", "infinity"]
