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

Complete the task. Where a seam supports a fast unit check, use /tdd (red-green-refactor); this repo has no unit-test framework, though — the pipelines are verified by running them against DuckDB (see FEEDBACK LOOPS), so treat that smoke-run as the behavioural check. Touch only files within the issue scope. Do not refactor adjacent code, do not bundle other issues' work, do not "improve" things that aren't broken.

# FEEDBACK LOOPS

Before committing, run all of:

- `make lint`         (`ruff check .` + `ruff format --check .`)
- `make test-newsapi` and/or `make test-trends` — run whichever pipeline(s) the issue touches. If you changed shared code (`utils.py`, `.dlt/`, `pyproject.toml`), run both.

Every gate must exit 0. If a gate fails, fix and re-run. Do not commit on red. (`make fix` auto-applies ruff fixes if lint is the only failure.)

# CODE REVIEW

Once the gates are green, run `/code-review` on your diff (two-axis: Standards + Spec against this issue). Address any blocking findings and re-run the gates before committing.

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
