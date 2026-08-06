# Plan: ODCS + datacontract-cli + dbt-duckdb demo repo (NewsAPI via dlt)

**Date:** 2026-08-06
**Repo:** `/Users/ekoepplin/repos/dbt-data-contract-workflow` (currently empty)
**Purpose:** Teaching demo showing how to author, publish, and enforce Open Data Contract Standard (ODCS) v3.1.0 contracts inside a dbt project, using the [datacontract-cli](https://docs.datacontract.com/) as enforcement engine and NewsAPI (via dlt) as source data.

---

## 1. Requirements Summary

**In scope**
- A runnable, clone-and-go dbt project on DuckDB
- dlt-based ingestion of NewsAPI articles (adapted from `/Users/ekoepplin/repos/dbt-bigquery-core/dlt-data-dumper/newsapi_pipeline.py`)
- ODCS v3.1.0 YAML data contracts at two layers: raw (dlt output) and staging (dbt output)
- Single, well-crafted end-to-end contract per layer covering: schema, quality rules, SLA, terms, servers
- Automated contract enforcement wired into `dbt build` via `on-run-end` hook (or Makefile target invoked after `dbt build`)
- Tutorial-quality README walking a reader from clone → API key → `make demo` → contract fail/pass demonstration

**Out of scope**
- BigQuery / cloud deployment (DuckDB only)
- Multi-adapter portability demo
- GitHub Actions CI (README stub only; wiring left as exercise)
- Progressive contract versioning walkthrough (single mature contract, not v1→v2→v3)
- Multi-contract showcase (single end-to-end per layer, not one-per-ODCS-section)

**Assumptions**
- User has a free NewsAPI.org key (30-day historical window is fine for demo)
- Reader has Python 3.11+ and `uv` installed (or `pipx`/`pip` fallback documented)
- ODCS v3.1.0 is the target spec; `datacontract-cli` (`pip install datacontract-cli`) is the enforcement engine
- `dbt-core >= 1.8`, `dbt-duckdb >= 1.8` (native constraints + `contract: enforced` support)

---

## 2. Acceptance Criteria (testable)

1. **Fresh clone runs end-to-end:** `git clone && cp .env.example .env && <edit NEWSAPI_KEY> && make demo` produces a populated `newsapi_articles.duckdb` and prints `✓ contracts pass` for both raw and staging layers.
2. **Contract failure is demonstrable:** A documented one-line edit (e.g., change `title` to nullable in staging model, or drop a required column) causes `make contract-test` to exit non-zero with a readable violation message.
3. **Contract files validate against ODCS v3.1.0:** `datacontract lint contracts/*.odcs.yaml` exits 0.
4. **Both contracts populated with all five ODCS pillars:** each `.odcs.yaml` contains non-empty `schema`, `quality`, `servicelevelagreements` (SLA), `terms`, and `servers` sections. Grep confirms.
5. **dbt tests pass:** `dbt build` on freshly ingested data succeeds (all `not_null`/`unique`/custom tests green).
6. **README teaches, not just documents:** README has (a) 3-sentence "what is a data contract" primer, (b) annotated walkthrough of `contracts/newsapi_staging.odcs.yaml` explaining each ODCS section, (c) the fail-demo recipe from criterion 2, (d) links to ODCS spec + datacontract-cli docs.
7. **No secrets in repo:** `.env` gitignored; `.env.example` present with placeholder key; `dlt` secrets read from env, not from `.dlt/secrets.toml` committed to repo.

---

## 3. Implementation Steps

### Step 3.1 — Repo skeleton + Python env

Create:
```
dbt-data-contract-workflow/
├── .env.example                    # NEWSAPI_KEY=your_key_here
├── .gitignore                      # .env, .venv, target/, dbt_packages/, *.duckdb, .dlt/secrets.toml
├── Makefile                        # ingest / build / contract-test / demo / clean
├── pyproject.toml                  # uv-managed deps
├── README.md                       # tutorial
├── dlt_ingest/
│   ├── __init__.py
│   ├── newsapi_pipeline.py         # adapted from source repo
│   └── .dlt/config.toml            # dataset_name, schema_name (no secrets)
├── contracts/
│   ├── newsapi_raw.odcs.yaml
│   └── newsapi_staging.odcs.yaml
└── dbt_project/
    ├── dbt_project.yml
    ├── profiles.yml                # duckdb, path: ../newsapi_articles.duckdb
    ├── packages.yml                # dbt_expectations, dbt_utils
    ├── models/
    │   ├── sources.yml             # dlt-loaded tables declared as sources
    │   └── staging/
    │       ├── stg_newsapi__articles.sql
    │       └── stg_newsapi__articles.yml
    └── macros/
        └── run_contract_tests.sql  # on-run-end hook shells out to datacontract CLI
```

`pyproject.toml` deps:
- `dlt[duckdb]`
- `newsapi-python`
- `dbt-core >= 1.8`
- `dbt-duckdb >= 1.8`
- `datacontract-cli`
- `loguru`

### Step 3.2 — Copy and trim dlt pipeline

- Copy `/Users/ekoepplin/repos/dbt-bigquery-core/dlt-data-dumper/newsapi_pipeline.py` → `dlt_ingest/newsapi_pipeline.py`
- Trim from 7 locales → 2 (`get_articles_us_en`, `get_articles_de_de`) to keep API calls low and demo tight
- Remove BigQuery branch — hardcode DuckDB destination at `./newsapi_articles.duckdb` (relative to repo root)
- Replace `dlt.config[...]` schema-name lookup with a plain `dataset_name="newsapi_raw"` to reduce config surface for readers
- Read `NEWSAPI_KEY` from env (dlt convention: `SOURCES__NEWSAPI_PIPELINE__GET_ARTICLES_US_EN__API_KEY` or simpler — a single top-level `NEWSAPI_KEY` env passed explicitly)

### Step 3.3 — dbt project scaffolding

- `dbt_project.yml`: profile `newsapi_demo`, model paths `models/`, target `dev`
- `profiles.yml`: single `newsapi_demo` profile with `duckdb` target pointing at `../newsapi_articles.duckdb`
- `models/sources.yml`: declare `newsapi_raw.articles_us_en` and `newsapi_raw.articles_de_de` as dbt sources
- `models/staging/stg_newsapi__articles.sql`: unions both locales, projects to the contract shape (see 3.4)
- `models/staging/stg_newsapi__articles.yml`: enable native dbt contract (`config: {contract: {enforced: true}}`), declare column types + constraints matching the ODCS contract

Adapt the schema pattern from `/Users/ekoepplin/repos/dbt-bigquery-core/dbt-bigquery-core/models/staging/newsapi/stg_newsapi__articles_us_en.sql:1-13` (columns: `source_name`, `author`, `title`, `description`, `url`, `image_url`, `published_at`, `content`, `language_code`, `_dlt_load_id`, `_dlt_id`).

### Step 3.4 — Author ODCS v3.1.0 contracts

Bootstrap workflow (documented in README):
1. Run `make ingest` once so DuckDB has real tables
2. `datacontract init contracts/newsapi_raw.odcs.yaml --from duckdb://... --table articles_us_en`
3. Hand-edit the generated YAML to add `quality`, `servicelevelagreements`, `terms`, `servers` sections
4. Repeat for staging

Both contracts must include:
- **`info`** — `title`, `version`, `owner`, `contact`, `status: active`
- **`servers`** — DuckDB path
- **`schema`** — models + fields with types, `required`, `unique`, descriptions
- **`quality`** — SQL/library quality checks (row count > 0, url regex, title length 5-500, language_code ∈ {en, de}, `published_at` within last 30 days)
- **`servicelevelagreements`** — freshness (≤ 24h), availability, latency
- **`terms`** — usage, limitations, billing note (free NewsAPI tier), noticePeriod
- **`support`** — link to repo issues

### Step 3.5 — Wire enforcement

Two integration surfaces:

**A. dbt `on-run-end` hook** (`macros/run_contract_tests.sql` + `dbt_project.yml`):
```yaml
on-run-end:
  - "{{ run_contract_tests() }}"
```
Macro shells out (`dbt.run_query` won't work — use `log` + a Makefile fallback). Realistically: use `on-run-end` to `log` a reminder, and have `make build` chain `dbt build && datacontract test contracts/*.odcs.yaml`. Choose the Makefile approach as primary; document the `on-run-end` hook variant in README as an alternative.

**B. Makefile targets:**
```
make ingest         # python -m dlt_ingest.newsapi_pipeline
make build          # dbt build --project-dir dbt_project
make contract-test  # datacontract test contracts/newsapi_raw.odcs.yaml && datacontract test contracts/newsapi_staging.odcs.yaml
make demo           # ingest + build + contract-test
make clean          # rm duckdb, target/, .dlt/pipelines
```

### Step 3.6 — Write README (the actual teaching artifact)

Sections:
1. **What this repo shows** — 3 sentences: ODCS = spec, datacontract-cli = enforcer, dbt = transformation + native constraints; together they gate a pipeline
2. **Architecture diagram** (ASCII) — NewsAPI → dlt → DuckDB (raw) → dbt → DuckDB (staging), with contract gates marked at both storage points
3. **Quickstart** — 4 commands to run demo
4. **Anatomy of a contract** — walk through `contracts/newsapi_staging.odcs.yaml` section by section, cross-referencing ODCS v3.1.0 docs
5. **How enforcement works** — dbt native `contract: enforced` (structural) vs. datacontract-cli (semantic quality + SLA); why you want both
6. **Break the contract (demo)** — one-line edits that trigger failures at each layer
7. **Extending** — swap DuckDB for BigQuery/Snowflake, add CI, version contracts

### Step 3.7 — Verify + polish

Run `make clean && make demo` from a fresh clone in a scratch worktree. Then run the "break the contract" recipe and confirm the failure message is clear.

---

## 4. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **NewsAPI rate limits / key required** | README states free key needed; trim to 2 locales; cache seed data as fallback CSV committed to `dbt_project/seeds/newsapi_seed_articles.csv` so demo works offline (dlt path AND seed path both documented) |
| **datacontract-cli DuckDB support gaps** | Verify `datacontract test --server duckdb` works in current CLI version before committing to it. If not, fall back to `datacontract test --schema` (structural only) + `dbt test` (quality) with README noting the split |
| **ODCS v3.1.0 vs. datacontract-cli version drift** | Pin `datacontract-cli` version in `pyproject.toml`; note supported ODCS version in README |
| **dbt native contracts vs. ODCS contracts confusion** | README dedicates a section to the distinction: dbt `contract: enforced` = compile-time structural check on model output; ODCS + datacontract-cli = spec + runtime data-quality/SLA validation. They complement, not compete |
| **Secrets leakage from copied `.dlt/` configs** | `.gitignore` explicitly excludes `.dlt/secrets.toml`; `.dlt/config.toml` contains only non-secret settings; `.env.example` documents required env vars |
| **`on-run-end` shell-out is awkward in dbt** | Primary path is Makefile chaining; `on-run-end` is optional/documented as alternative, not load-bearing |
| **Reader gets lost in ODCS spec size** | README walks *one* contract in detail rather than referencing full spec; annotated inline |

---

## 5. Verification Steps

Run in order after implementation:

1. `rm -rf .venv newsapi_articles.duckdb dbt_project/target dbt_project/dbt_packages` (clean slate)
2. `uv sync` (installs pyproject deps)
3. `cp .env.example .env && echo "NEWSAPI_KEY=<real key>" >> .env`
4. `make ingest` → expect `newsapi_articles.duckdb` created, two tables in `newsapi_raw` dataset with row_count > 0
5. `make build` → expect `dbt build` success, `stg_newsapi__articles` model materialized
6. `make contract-test` → expect both contracts pass, zero exit
7. `datacontract lint contracts/*.odcs.yaml` → exit 0
8. **Break-demo:** delete `not null` constraint on `title` in `stg_newsapi__articles.yml`, then insert a row with NULL title via `duckdb`, then rerun `make contract-test` → expect non-zero exit with readable message
9. **README dry-read:** hand README to someone who has never seen ODCS, ask if they can (a) explain what a contract is, (b) point to the file that gates staging, (c) describe how to make the pipeline fail. If not, revise.

---

## 6. Open Decisions (deferred to implementation, not blockers)

- **Seed fallback data**: commit a 20-row CSV snapshot of NewsAPI response for offline demo? *Recommended: yes, keeps demo working without a key.*
- **dbt package pins**: `dbt-labs/dbt_utils`, `calogica/dbt_expectations` — pin latest compatible.
- **Whether to include a `docs/` folder with rendered contract HTML** (via `datacontract export --format html`): nice-to-have; add if trivial.

---

## Appendix — Files to be Created

| Path | Purpose | Lines (est.) |
|------|---------|--------------|
| `.env.example` | env template | 3 |
| `.gitignore` | secrets/artifacts | 15 |
| `Makefile` | task runner | 40 |
| `pyproject.toml` | uv deps | 25 |
| `README.md` | tutorial | 300 |
| `dlt_ingest/newsapi_pipeline.py` | ingestion | ~80 (trimmed from 178) |
| `dlt_ingest/.dlt/config.toml` | non-secret dlt config | 5 |
| `contracts/newsapi_raw.odcs.yaml` | raw contract | ~100 |
| `contracts/newsapi_staging.odcs.yaml` | staging contract | ~120 |
| `dbt_project/dbt_project.yml` | dbt config | 25 |
| `dbt_project/profiles.yml` | duckdb profile | 10 |
| `dbt_project/packages.yml` | dbt packages | 10 |
| `dbt_project/models/sources.yml` | dlt sources | 30 |
| `dbt_project/models/staging/stg_newsapi__articles.sql` | staging model | 25 |
| `dbt_project/models/staging/stg_newsapi__articles.yml` | staging schema + constraints | 60 |
| `dbt_project/macros/run_contract_tests.sql` | optional on-run-end hook | 10 |
