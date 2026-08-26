# MISSION

You work on ONE issue per run. The issue body has been injected above this prompt. Do not switch to other issues even if their numbers appear in references, drafts, or commit history. If your work would span multiple issues, stop and add a comment to the current issue explaining the dependency.

# PRE-CHECK

Before writing any code, verify the acceptance criteria are not already satisfied in the repo (file deletions, dependency removals, and pipeline additions sometimes ship in earlier commits without the issue being closed). If they are already satisfied:

```
gh issue close <N> --repo ekoepplin/dbt-data-contract-workflow -c "Already shipped in <sha>"
```

Then exit. Do not invent work.

# EXPLORATION

Explore the repo. Read `docs/adr/` for architectural decisions and `CONTEXT.md` for domain vocabulary. If a per-issue draft exists at `tasks/drafts/issue-*.md` matching this issue number, read it.

# IMPLEMENTATION

Complete the task. Where a seam supports a fast unit check, invoke the `/tdd` skill (red-green-refactor); this repo has no unit-test framework, though — the pipelines are verified by running them against DuckDB (see FEEDBACK LOOPS), so treat that smoke-run as the behavioural check. Touch only files within the issue scope. Do not refactor adjacent code, do not bundle other issues' work, do not "improve" things that aren't broken.

# FEEDBACK LOOPS

This repo has no `make lint`/`ruff` and no unit-test framework — its pipelines are verified by running them against DuckDB. Before committing, run whichever of the real Makefile targets are relevant to your change, and confirm each exits 0:

- `make contract-lint` — structural (ODCS shape) validation of both contracts. Run if you touched `contracts/*.odcs.yaml`.
- `make build` (`deps` + `dbt build`) — compiles, runs, and tests all dbt models; enforces contracts at runtime. Run if you touched `dbt_project/` or a contract that gates it.
- `make demo` (`ingest` + `deps` + `contract-lint` + `build`) — the full pipeline end to end. Run if you touched `dlt_ingest/` or anything upstream of ingestion.
- `make contract-export` — regenerates `contracts/generated/*.yml` from the ODCS contracts. Run if you touched a contract and want to sanity-check the derived dbt YAML (not required otherwise — `contracts/generated/` is gitignored).
- `make notebook-check` — verifies the Jupyter kernel, dev-group packages, and the `nbstripout` filter. Run if you touched `notebooks/`, `.devcontainer/`, or the dev dependency group in `pyproject.toml`.
- `make install` — `uv sync`; run first if your change touched `pyproject.toml`/the lockfile.
- `make clean` — resets DuckDB/dbt/dlt state if you need a clean slate before re-running a gate.

Every gate you run must exit 0. If a gate fails, fix and re-run. Do not commit on red.

# CODE REVIEW

Once the gates are green, invoke the `/code-review` skill against this issue as the spec source (two-axis: Standards + Spec). Your changes are uncommitted, so there is no separate fixed point to pin: tell the skill explicitly to review `git diff HEAD` (working tree vs. `HEAD`, not a `<fixed-point>...HEAD` merge-base comparison — `HEAD...HEAD` is always empty). Address any blocking findings and re-run the gates before committing.

# STAGING DISCIPLINE

Use `git add -- <specific paths>`. NEVER `git add -A` or `git add .` — they sweep up unrelated working-tree WIP and bundle it into your commit, breaking attribution.

Before every commit, run `git diff --staged --name-only` and verify every staged path is either named in the issue body or is a test/doc/lock-file directly produced by this issue's work. Unstage anything else:

```
git reset HEAD -- <path>
```

If you cannot identify why a file is staged, unstage it. Better to under-commit and let a follow-up run pick it up than to over-commit and pollute history.

# COMMIT

Make ONE atomic commit for this issue. Stage only the files within issue scope. The commit message must:

1. Use conventional-commit prefix (`feat:`, `fix:`, `refactor:`, `docs:`, etc.)
2. State key decisions made
3. End with a `Closes #<N>` trailer so GitHub auto-closes the issue on push

# KANBAN

GitHub auto-closes the issue from the `Closes #<N>` trailer once you push. There is no `move-issue.sh` in this repo, so the kanban card is moved manually — do not attempt to run a board-mover script.

If you cannot finish in this run, leave a comment summarising what's done and what remains, then exit:
```
gh issue comment <N> --repo ekoepplin/dbt-data-contract-workflow --body "..."
```

Do NOT close the issue with partial work.
