# PROJECT-INFO

Orientation doc for anyone (human or agent) picking up this repo cold. It
describes what's actually here, validated against the current tree and
`git log` — not the aspirational version. For the deep-dive on data
contracts, see [`README.md`](README.md) and
[`GETTING_STARTED_DATA_CONTRACT_CLI.md`](GETTING_STARTED_DATA_CONTRACT_CLI.md).

## What this is

A **teaching demo** for enforcing [ODCS v3.1.0](https://bitol-io.github.io/open-data-contract-standard/v3.1.0/)
data contracts inside a dbt project, using `datacontract-cli` as the
enforcement engine and `dlt` to ingest from NewsAPI. Everything runs locally
against **DuckDB** — no cloud account needed.

```
NewsAPI.org → dlt (dlt_ingest/newsapi_pipeline.py) → DuckDB (newsapi_raw)
            → contracts/newsapi_raw.odcs.yaml         [gate 1: contract-lint]
            → dbt (dbt_project/models/staging/)        → DuckDB (main)
            → contracts/newsapi_staging.odcs.yaml       [gate 2: contract-lint + dbt test]
```

Two ODCS contracts gate the pipeline: one on the raw dlt output, one on the
dbt staging output. `datacontract lint` validates contract *shape*;
`dbt build`/`dbt test` enforces the *runtime* rules against live data
(`datacontract test` itself doesn't support a DuckDB server as of
`datacontract-cli 1.1.0` — see `GETTING_STARTED_DATA_CONTRACT_CLI.md`).

## Repo layout

| Path | What |
|---|---|
| `dlt_ingest/newsapi_pipeline.py` | dlt source: NewsAPI (US-en, DE-de) → DuckDB |
| `contracts/*.odcs.yaml` | The two ODCS contracts (raw, staging) |
| `contracts/generated/` | Derived dbt YAML from `make contract-export` (gitignored, regenerate locally) |
| `dbt_project/` | dbt project (DuckDB target); `models/staging/stg_newsapi__articles` |
| `notebooks/` | Jupyter notebooks; kernel runs against the repo's `.venv` (see ADR below) |
| `Makefile` | Every workflow entrypoint — run `make help` |
| `Dockerfile` / `.devcontainer/` | devcontainer for a zero-setup VS Code environment |
| `docs/adr/` | Architecture decision records |
| `docs/agents/` | Conventions for AI agents working this repo (issue tracker, domain docs) |
| `agentic-workflow/ralph/` | A headless-agent loop that works GitHub issues unattended — see below |

## Running it

```bash
make install   # uv sync
cp .env.example .env   # add NEWSAPI_KEY
make demo      # ingest -> deps -> contract-lint -> dbt build
```

Or open in the devcontainer ("Reopen in Container") — `postCreateCommand`
runs `uv sync`, `dbt deps`, installs the `nbstripout` git filter, and wires
up the `mattpocock-skills` Claude Code plugin automatically. Run
`make notebook-check` after a fresh container build to confirm the Jupyter
kernel, dev-group packages (`ipykernel`, `duckdb`, `pandas`), and the
`nbstripout` filter are all actually working — not just that the config
files look right.

Run `make help` for the full target list; it's kept current with the
Makefile as targets are added.

## The `agentic-workflow/ralph/` loop

`afk.sh` / `once.sh` drive Claude Code headlessly, one GitHub issue at a
time, against `ekoepplin/dbt-data-contract-workflow`: `afk.sh` polls issue
state and calls `once.sh` up to `MAX` times (default 10) until the issue
closes; `once.sh` builds a prompt from the live issue body + `prompt.md`
(the fixed instructions: explore, implement in-scope only, run feedback-loop
gates, code-review, one atomic commit, `Closes #<N>` trailer) and runs
`claude --settings settings.ralph.json`. `settings.ralph.json` allow-lists
the exact `Bash`/`gh`/`git` invocations the loop is permitted to run
unattended. It supports three backends (`anthropic`, `vllm`, `ollama`),
configured via `.env.ralph` (gitignored).

**Known gap, validated against this repo's actual tooling:** `prompt.md`'s
FEEDBACK LOOPS step requires `make lint`, `make fix`, `make sync`,
`make test-newsapi`, and `make test-trends` to pass before every commit —
none of these targets exist in `Makefile` (whose actual targets are
`help install ingest deps build contract-lint contract-export demo
notebook-check clean`), and `ruff` isn't a project dependency. `prompt.md`
was carried over from a different project's template and hasn't been
adapted to this repo yet. Until it is, every `once.sh` run will fail at the
first gate. (`Makefile`'s `.PHONY` line also still lists a `test` target
that was never defined — a separate, pre-existing gap.)

## Conventions for agents

- **Issues**: GitHub Issues on this repo; see `docs/agents/issue-tracker.md`
  for the `gh` CLI conventions this project uses.
- **Domain docs**: `docs/adr/` for architecture decisions (currently just
  ADR-0001, VS Code-native Jupyter over a standalone server). No
  `CONTEXT.md` exists yet — per `docs/agents/domain.md`, that's created
  lazily by the domain-modeling skill once terms/decisions need recording,
  not something to add speculatively.
- **CLAUDE.md** at the repo root points here and at the two `docs/agents/`
  files above; keep it as the short index and put substance in this file or
  the referenced docs instead of growing CLAUDE.md directly.
