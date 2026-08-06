# dbt-data-contract-workflow

**A teaching demo:** how to author, publish, and enforce
[Open Data Contract Standard (ODCS) v3.1.0](https://bitol-io.github.io/open-data-contract-standard/v3.1.0/)
contracts inside a dbt project, using the
[datacontract CLI](https://docs.datacontract.com/) as the enforcement engine and
[dlt](https://dlthub.com/) to ingest data from the
[NewsAPI](https://newsapi.org/).

Everything runs locally on **DuckDB** — no cloud account needed.

---

## What is a data contract?

A **data contract** is a machine-readable, human-friendly spec of what a dataset
*is*: its schema, its quality guarantees, its SLAs, its terms of use, and where
it lives. **ODCS** is the open standard; the **datacontract CLI** is one
implementation that can validate a live dataset against the spec. Together they
turn "trust me, this table is fine" into a checkable artifact that lives in
source control.

This repo shows a minimal-but-complete example: two contracts (raw + staging),
wired into a dbt project, enforced automatically as part of the build.

---

## Architecture

```
   NewsAPI.org
        │
        ▼
   ┌────────────┐
   │    dlt     │   dlt_ingest/newsapi_pipeline.py
   └─────┬──────┘
         │
         ▼
   ┌────────────┐     ┌──────────────────────────────┐
   │  DuckDB    │◄────┤  contracts/newsapi_raw.odcs  │
   │ newsapi_raw│     │  (RAW contract — gate 1)     │
   └─────┬──────┘     └──────────────────────────────┘
         │
         ▼
   ┌────────────┐
   │    dbt     │   dbt_project/models/staging/*
   └─────┬──────┘
         │
         ▼
   ┌────────────┐     ┌──────────────────────────────┐
   │  DuckDB    │◄────┤ contracts/newsapi_staging    │
   │   main     │     │ (STAGING contract — gate 2)  │
   └────────────┘     └──────────────────────────────┘
         │
         ▼
      Consumers
```

Each contract file is a YAML document conforming to ODCS v3.1.0. The
`datacontract test` command connects to DuckDB, reads the tables, and asserts
they match the schema + quality rules declared in the contract.

---

## Quickstart

**Prerequisites:** Python 3.11+, [`uv`](https://docs.astral.sh/uv/), and a free
[NewsAPI key](https://newsapi.org/register).

```bash
git clone <this-repo>
cd dbt-data-contract-workflow

cp .env.example .env
# edit .env and set NEWSAPI_KEY=<your key>

make install     # uv sync
make demo        # ingest + contract-lint + dbt build (runs all tests)
```

Expected outcome: NewsAPI articles land in `./newsapi_articles.duckdb`, both
ODCS contracts lint clean, dbt builds `stg_newsapi__articles`, and all
runtime tests pass.

### Devcontainer

Open the repo in VS Code, "Reopen in Container" — the `.devcontainer/`
config builds the `development` target of `Dockerfile` (Python 3.11, uv,
DuckDB CLI, zsh, dbt + dlt + datacontract-cli extensions installed) and runs
`uv sync` automatically. Everything below then works identically inside the
container.

---

## Repo layout

```
dbt-data-contract-workflow/
├── dlt_ingest/newsapi_pipeline.py     # dlt source (adapted from an internal repo)
├── contracts/
│   ├── newsapi_raw.odcs.yaml          # gate 1 — raw dlt output
│   └── newsapi_staging.odcs.yaml      # gate 2 — dbt staging output
├── dbt_project/
│   ├── dbt_project.yml
│   ├── profiles.yml                   # DuckDB target
│   ├── packages.yml                   # dbt_utils, dbt_expectations
│   ├── models/
│   │   ├── sources.yml
│   │   └── staging/
│   │       ├── stg_newsapi__articles.sql
│   │       └── stg_newsapi__articles.yml   # dbt native `contract: enforced`
│   └── macros/run_contract_tests.sql  # optional on-run-end hook
├── Makefile                            # ingest / build / contract-test / demo / clean
├── pyproject.toml                      # uv-managed deps
└── README.md
```

---

## Anatomy of a contract

Open `contracts/newsapi_staging.odcs.yaml`. Every ODCS v3.1.0 contract has the
same five load-bearing sections:

### 1. `info` (top-level fields)

Identity metadata: `apiVersion`, `id`, `name`, `version`, `status`, `domain`,
`tenant`. This is how a data catalog would index the contract.

### 2. `servers`

Where the data physically lives. In this demo it's a local DuckDB file; in
production you'd point at BigQuery, Snowflake, S3, Kafka, etc.

```yaml
servers:
  - server: duckdb-local
    type: duckdb
    path: ./newsapi_articles.duckdb
    schema: main
```

### 3. `schema`

Column-level types, required-ness, uniqueness, and descriptions. This is the
structural contract — the thing that fails if a producer drops a column or
changes a type.

```yaml
schema:
  - name: stg_newsapi__articles
    properties:
      - name: title
        logicalType: string
        physicalType: VARCHAR
        required: true
```

### 4. `quality`

SQL-based (or library-based) data-quality assertions. This is the semantic
contract — it fails if the data is *shaped right* but *content is wrong*
(e.g., a URL that isn't a URL, a title of length 0).

```yaml
quality:
  - type: sql
    description: All URLs must be http(s).
    query: SELECT COUNT(*) FROM stg_newsapi__articles WHERE url NOT LIKE 'http%'
    mustBe: 0
```

### 5. `servicelevelagreements`, `terms`, `team`, `support`

The **social contract**: how fresh, how long retained, how available, who
owns it, who to page when it breaks. Often overlooked and often the reason
data pipelines rot in the first place.

---

## How enforcement works

Three complementary enforcement mechanisms sit on top of the same ODCS
contract files:

| Layer | Tool | What it catches |
|-------|------|-----------------|
| **Structural (contract shape)** | `datacontract lint` | Malformed ODCS YAML — missing required fields, wrong types, unknown properties. Runs in `make contract-lint`. |
| **Structural (dbt native)** | `dbt build` with `contract: enforced` on `stg_newsapi__articles` | Compile-time drift between the model output and the declared columns/types/constraints |
| **Runtime (data quality)** | `dbt test` (invoked by `dbt build`) — reads `dbt_expectations` + `not_null` + `unique` + `accepted_values` tests | Live data pathologies: bad URLs, wrong-length titles, out-of-set language codes, duplicate `_dlt_id`s |

You want **all three**: lint catches contract-authoring mistakes; dbt native
catches accidental structural changes; dbt tests catch real-world data
pathologies (e.g. a NewsAPI outage returning empty payloads or malformed URLs).

`make demo` runs them in order: `contract-lint` first (static gate), then
`dbt build` (structural + runtime gate on live data).

### Contract → dbt bridge

`make contract-export` runs `datacontract export dbt-sources` and
`dbt-models` against both ODCS files and writes the results to
`contracts/generated/`. These are the dbt YAML fragments the CLI would
build from your contract — use them to keep `models/sources.yml` and the
staging model YAML in sync with the contract as it evolves. Commit the
generated files if you want reviewers to see the derived shape in diffs.

### A note on `datacontract test`

The `datacontract test` subcommand runs SQL quality checks directly against
a configured server. As of `datacontract-cli 1.1.0`, the `duckdb` server
type is declared in the ODCS 3.1.0 schema but **not wired in the runtime
engine** — attempting to run `datacontract test` against our contracts
prints `Server type duckdb not yet supported by datacontract CLI`. This
demo therefore routes runtime enforcement through `dbt test`, which reads
the same expectations from the model YAML. When duckdb-server support
lands upstream, you can add a `contract-test` Makefile target that calls
`datacontract test contracts/*.odcs.yaml` and get parallel enforcement.

---

## Break the contract (demo)

The most instructive thing you can do with this repo is intentionally break
each contract and watch it fail.

### Break 1: violate a runtime quality rule (dbt test)

After a successful `make demo`, inject a bad row and rerun tests:

```bash
duckdb newsapi_articles.duckdb -c \
  "INSERT INTO main.stg_newsapi__articles VALUES
   ('BadSource', NULL, 'ok-length title', NULL, 'ftp://bad.example',
    NULL, CURRENT_TIMESTAMP, NULL, 'en', 'manual', 'manual-1');"
uv run dbt test --project-dir dbt_project --profiles-dir dbt_project
```

Expected: the `dbt_expectations.expect_column_values_to_match_regex` test on
`url` fails — the row has `ftp://` but the contract requires `^https?://`.

### Break 2: violate the dbt native structural contract

Edit `dbt_project/models/staging/stg_newsapi__articles.yml` — change the
`title` column's `data_type` from `varchar` to `integer`, then run
`make build`. Expected: dbt aborts at model creation with a contract
violation because the actual output type doesn't match the declared type.

### Break 3: violate the ODCS contract itself (contract-lint)

Edit `contracts/newsapi_staging.odcs.yaml` — delete the required
`apiVersion:` line, then run `make contract-lint`. Expected: red output,
non-zero exit, the linter names the missing field.

### Bonus: regenerate the dbt bridge

Change a description in `contracts/newsapi_raw.odcs.yaml`, then run
`make contract-export`. Diff `contracts/generated/dbt_sources_from_raw.yml`
to see the change flow through to the derived dbt YAML.

---

## Extending

- **Swap the destination.** Change `servers.type` in each contract and update
  `profiles.yml` / dlt destination. Contracts are portable across DuckDB,
  Postgres, BigQuery, Snowflake, Databricks.
- **Add CI.** Wire `make lint-contracts && make demo` into GitHub Actions on
  PR. Fail the build if either contract violates.
- **Version contracts.** Bump `version:` in the contract on breaking changes.
  Use `datacontract changelog <old-file> <new-file>` to compare two versions
  (e.g. `datacontract changelog <(git show HEAD~1:contracts/newsapi_staging.odcs.yaml) contracts/newsapi_staging.odcs.yaml`).
- **Publish to a catalog.** `datacontract publish` pushes contracts to
  Data Mesh Manager or a similar registry.
- **More locales.** The trimmed dlt pipeline handles US-en + DE-de; the source
  version supported 7. Re-add and update the contracts' `language_code`
  quality rule.

---

## References

- ODCS v3.1.0 spec: https://bitol-io.github.io/open-data-contract-standard/v3.1.0/
- datacontract CLI docs: https://docs.datacontract.com/
- dlt docs: https://dlthub.com/docs/
- dbt native model contracts: https://docs.getdbt.com/docs/collaborate/govern/model-contracts

---

## Credits

The dlt pipeline is adapted from an internal `dbt-bigquery-core` repo; here
it's trimmed to two locales and pinned to a local DuckDB destination for
teaching purposes.
