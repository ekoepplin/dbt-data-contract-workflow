# Presentation Outline: Schema Contracts → Data Contracts in dbt

Internal team session, ~35 min (30 talk + ~5 buffer for questions mid-flow).
No slide deck — this is a run-of-show for presenting `GETTING_STARTED_DATA_CONTRACT_CLI.md`
and this repo's code/CLI directly. Each section names the file/command to have
open and the point to land before moving on.

Pre-flight (do before people join):
- `git pull` to confirm you're on `a20b624`+ (published_at TIMESTAMP WITH TIME ZONE fix, mart demo staged)
- Terminal open at repo root, `.venv` activated
- Have `README.md`, `GETTING_STARTED_DATA_CONTRACT_CLI.md`, and the four contract/model
  files below open in tabs
- Optional safety net: `GETTING_STARTED_DATA_CONTRACT_CLI.md` has verbatim transcripts
  of every command below — if live output diverges or a command hangs, read from the
  doc rather than debugging live

---

## 1. Cold open — what problem are we solving? (2 min)

No demo yet. State the problem in one breath: dbt models change shape silently;
downstream consumers (dashboards, other teams, ML features) find out when
something breaks, not before. Two separate mechanisms exist to prevent that,
and this repo wires both together:

- **dbt-native schema contracts** — enforced at `dbt build` time, inside the project
- **ODCS data contracts** (via `datacontract-cli`) — the "social contract" layer:
  schema + quality rules + SLAs + ownership, portable outside dbt

Today: what each one is, how they compose, and where the seams actually are
(including two real bugs this repo hit while being built).

---

## 2. dbt-native schema contracts (8 min)

**Show:** `dbt_project/models/staging/stg_newsapi__articles.yml`

- Point at `config: contract: enforced: true` and the `data_type` + `constraints`
  on each column — this is dbt's own mechanism, no extra tooling.
- Explain: dbt checks the model's *compiled* output schema against this
  declaration at build time. Mismatch → build fails before a bad table ever
  lands.

**Live demo — break it on purpose:**
```bash
# temporarily change a data_type in the yml, e.g. published_at -> varchar
DBT_DUCKDB_PATH=$PWD/newsapi_articles.duckdb .venv/bin/dbt build \
  --select stg_newsapi__articles --project-dir dbt_project --profiles-dir dbt_project
```
Show the `assert_columns_equivalent` failure table dbt prints (same shape as the
real one this repo hit — see §5). Revert the edit, rebuild clean to close the loop.

**Land the point:** this is real, it's free (built into dbt-core), and it's
already running in this repo on every `dbt build`. It's also *local to this
project* — nothing outside dbt knows this contract exists. That's the gap
ODCS + datacontract-cli fills, next.

---

## 3. Enter ODCS + datacontract-cli (5 min)

**Show:** `contracts/newsapi_staging.odcs.yaml`

- Walk the shape: `schema` (same idea as dbt's contract, richer typing),
  `quality` (SQL-rule checks beyond just types/nulls), `slaProperties`,
  `team`/`support`, `customProperties` — the parts dbt has no concept of at all.
- One line: ODCS is a spec, `datacontract-cli` is the tool that understands it
  and can talk to dbt.
- Show `README.md`'s "How enforcement works" 3-layer table (`datacontract lint`
  → dbt native contract → `dbt test`) — this repo actually runs all three.

```bash
uv run datacontract lint contracts/newsapi_staging.odcs.yaml
```
**Land the point:** `lint` is pure structural validation of the YAML — it does
NOT touch dbt or the database. That distinction matters for what's coming next.

---

## 4. The three ways datacontract-cli talks to dbt (15 min)

**Show:** `GETTING_STARTED_DATA_CONTRACT_CLI.md`, table at the top (§0/intro).

Three directions exist — name all three in one breath, then spend almost all
the time on the middle one:

| Direction | Command | One-liner |
|---|---|---|
| Model-first (export) | `datacontract export dbt-sources/dbt-models` | one-shot dump, contract → dbt YAML |
| **Contract-first (sync)** | `datacontract dbt sync` | **live, repeatable — the main demo** |
| Data-first (import) | `datacontract import dbt` | dbt manifest → draft contract skeleton |

### 4a. Contract-first `sync` — the live demo (12 min)

**Show:** `contracts/newsapi_mart.odcs.yaml` and
`dbt_project/models/marts/mart_newsapi__source_daily_counts.sql` — both already
in the repo (staged from this exact walkthrough).

Narrate the mermaid flow in `GETTING_STARTED_DATA_CONTRACT_CLI.md` §2.0 first
(30 sec, it's the map for what you're about to run), then run for real:

```bash
uv run datacontract dbt sync contracts/newsapi_mart.odcs.yaml --project-dir dbt_project
```
- Point out: this **updates** the model's `.yml` in place, generates a singular
  SQL test file from the `quality:` rule — real, on disk, not a preview.
- Explain the guardrail: sync needs the `.sql` file to already exist — it will
  never invent your transformation logic, only scaffold the schema/tests around
  it. (Mention the WARNING path from §2.0/§2.1 verbally — you don't need to
  reproduce it live by deleting the stub, just explain what it looks like.)

```bash
DBT_DUCKDB_PATH=$PWD/newsapi_articles.duckdb .venv/bin/dbt build \
  --select mart_newsapi__source_daily_counts --project-dir dbt_project --profiles-dir dbt_project

uv run datacontract dbt test contracts/newsapi_mart.odcs.yaml --project-dir dbt_project
```
**Land the point:** `dbt build` runs the generated `not_null` tests as normal
dbt tests. `datacontract dbt test` runs the *same* tests but reports them back
mapped to the contract's human-readable `quality:` descriptions — "Counts must
be positive" instead of a dbt test ID. That's the payoff: the contract's
language survives all the way to the test report.

### 4b. `export` and `import` — one slide each (3 min)

- **export** (`Makefile:44-48`, `make contract-export`): "I already changed the
  contract, regenerate the boilerplate" — one-shot, doesn't touch your real
  model files, you copy-paste. Useful for scaffolding a brand-new model fast.
- **import** (`datacontract import dbt --source manifest.json`): the mirror
  image — you already have a model with data flowing, no contract yet, and you
  want a draft to fill in. Reverse-engineers from dbt's compiled `manifest.json`
  (not the live DB — DuckDB isn't even a supported *source* type for import,
  only as a sync/test target). Produces a `status: draft` skeleton — no
  `quality:`, no `servers:`, no SLAs. Starting point, not a finished contract.

---

## 5. Gotchas — what actually went wrong building this (5 min)

Credibility section. Three real issues, each with a one-line "why it matters":

1. **`export` silently defaults to Snowflake-style types without `--server`**
   (`GETTING_STARTED...md` §1.1) — `TIMESTAMP_TZ` got committed into
   `contracts/generated/*.yml` for a DuckDB project. Fixed by always passing
   `--server duckdb-local`. `sync` doesn't have this bug — it auto-detects the
   single declared server.
2. **`sync` silently overwrites hand-written prose and casing on every run**
   (§4) — descriptions become the contract's wording, `varchar` → `VARCHAR`.
   Not wrong, but a diff you need to actually read in review, not skim past.
3. **The real one this repo hit**: every contract declared `published_at` as
   `TIMESTAMP`, but dlt infers `TIMESTAMP WITH TIME ZONE` from NewsAPI's UTC
   timestamps — nobody caught it because the pipeline had never been run
   end-to-end with real data before this week. `dbt build`'s contract
   enforcement (§2) caught it immediately the first time real data flowed
   through. Fixed by widening the contract, not by dropping the timezone.
   **This is the whole pitch for §2, proven, not hypothetical.**
4. **`datacontract test` doesn't support DuckDB in CLI 1.1.0** — it wants a
   live connection to whatever `servers:` declares; duckdb isn't wired into
   that engine yet. `sync`/`dbt test` sidestep this entirely by compiling to
   dbt-native tests instead (§6) — which is *why* this repo's enforcement
   routes through `dbt build`/`dbt test` rather than `datacontract test`.

---

## 6. Advantages / wrap-up (5 min)

Tie back to §1's problem statement:

- dbt contracts: free, local, catches shape drift at build time — but silent
  to anyone outside the dbt project.
- ODCS + datacontract-cli: makes the contract a portable artifact — ownership,
  SLAs, quality rules a non-dbt consumer can read — and `sync` keeps the dbt
  side generated rather than hand-maintained, so the two don't drift apart.
- The gotchas in §5 aren't reasons not to do this — they're the reason to run
  it against real data before you trust it, which is exactly what this repo
  now does (`make demo`, verified end-to-end).

**Close:** point at `make demo` as the one command that runs this entire stack
(ingest → contract lint → dbt build, all three enforcement layers) and offer
to run it live if there's time / on request.

---

## Timing summary

| Section | Time |
|---|---|
| 1. Cold open | 2 min |
| 2. dbt-native contracts + break-it demo | 8 min |
| 3. ODCS + datacontract-cli intro | 5 min |
| 4. Three directions (sync-centered) | 15 min |
| 5. Gotchas | 5 min |
| 6. Advantages / wrap-up | 5 min |
| **Total** | **40 min** (trim §4b or §5 item 1/2 to hit 30) |
