.PHONY: help install ingest deps build test contract-lint contract-export demo notebook-check clean

PY := uv run
DBT := $(PY) dbt
DBT_FLAGS := --project-dir dbt_project --profiles-dir dbt_project

# Absolute DuckDB path so `dbt build` works regardless of CWD (dbt-duckdb
# resolves relative paths from the process CWD, not the profiles dir).
export DBT_DUCKDB_PATH := $(CURDIR)/newsapi_articles.duckdb

help:
	@echo "Targets:"
	@echo "  install         uv sync (Python deps)"
	@echo "  deps            dbt deps (packages.yml)"
	@echo "  ingest          Run dlt pipeline -> DuckDB"
	@echo "  build           dbt build (compile + run + test) — enforces contracts at runtime"
	@echo "  contract-lint   datacontract lint on both ODCS contracts (structural)"
	@echo "  contract-export Export ODCS -> dbt sources/models YAML (regenerates from contracts)"
	@echo "  demo            ingest + deps + contract-lint + build"
	@echo "  notebook-check  Verify the reproducible notebook environment (kernel, deps, nbstripout)"
	@echo "  clean           Remove DuckDB, dbt target, dlt state"

install:
	uv sync

deps:
	$(DBT) deps $(DBT_FLAGS)

ingest:
	$(PY) python -m dlt_ingest.newsapi_pipeline

build: deps
	$(DBT) build $(DBT_FLAGS)

# Structural validation of both contracts (YAML shape, ODCS v3.1.0 schema).
contract-lint:
	@echo "== Linting raw contract =="
	$(PY) datacontract lint contracts/newsapi_raw.odcs.yaml
	@echo "== Linting staging contract =="
	$(PY) datacontract lint contracts/newsapi_staging.odcs.yaml

# Regenerate dbt sources + models YAML from ODCS contracts.
# The generated files live under contracts/generated/ and are meant as reference
# artifacts — copy fields into dbt_project/models/**/*.yml as the contract evolves.
contract-export:
	@mkdir -p contracts/generated
	$(PY) datacontract export dbt-sources contracts/newsapi_raw.odcs.yaml --server duckdb-local --output contracts/generated/dbt_sources_from_raw.yml
	$(PY) datacontract export dbt-models contracts/newsapi_staging.odcs.yaml --server duckdb-local --output contracts/generated/dbt_models_from_staging.yml
	@echo "Regenerated: contracts/generated/dbt_sources_from_raw.yml, contracts/generated/dbt_models_from_staging.yml"

demo: ingest deps contract-lint build
	@echo ""
	@echo "Demo complete."
	@echo "  - contracts linted (structural)"
	@echo "  - dbt build ran all tests (runtime quality)"
	@echo "Inspect newsapi_articles.duckdb."

# Verifies the reproducible-notebook-environment promise end to end: Jupyter
# tooling installed, project kernel registered, dev-group packages importable,
# nbstripout's git filter active. Confirms notebook support actually works on
# a freshly built devcontainer, not just that the config files look right.
notebook-check:
	@echo "== Jupyter tooling installed =="
	$(PY) jupyter --version
	@echo "== Project kernel registered =="
	$(PY) jupyter kernelspec list | grep -q python3
	@echo "== Dev-group packages importable =="
	$(PY) python -c "import ipykernel, duckdb, pandas"
	@echo "== nbstripout git filter active =="
	$(PY) nbstripout --status
	@echo ""
	@echo "notebook-check passed."

clean:
	rm -f newsapi_articles.duckdb newsapi_articles.duckdb.wal
	rm -rf dbt_project/target dbt_project/dbt_packages dbt_project/logs
	rm -rf .dlt/pipelines .dlt/pipeline_state
	rm -rf contracts/generated
	find . -type d -name __pycache__ -exec rm -rf {} +
