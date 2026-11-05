# Getting Started: GitHub Copilot CLI on a Fresh Machine

This is a setup guide for a machine that will have **GitHub Copilot CLI
only** — no Claude Code. It covers two things: getting Matt Pocock's
engineering skills (`grilling`, `domain-modeling`, `tdd`, `code-review`,
`to-spec`, `to-tickets`, …) working under Copilot CLI, and running this
repo's `agentic-workflow/ralph-copilot/` loop — the Copilot-CLI port of
`agentic-workflow/ralph/` tracked by
[#6](https://github.com/ekoepplin/dbt-data-contract-workflow/issues/6)–[#10](https://github.com/ekoepplin/dbt-data-contract-workflow/issues/10).

**Current repo state, as of writing**: the core loop (#8) and the skills
(#7) are in this repo. #9 (default-model config) and #10 (docs) are still
open. §4 describes the scripts as they exist, but they haven't been run
against a real issue with Copilot CLI yet, so it isn't a verified transcript,
matching how this repo already flags known gaps in `PROJECT-INFO.md` rather
than hiding them.

Facts below were checked against GitHub's own docs
(`docs.github.com/en/copilot/how-tos/copilot-cli/...`) and skills.sh's
Copilot CLI target page during a validation pass — cited inline. GitHub
Copilot CLI moves fast; if a command below doesn't match what you see,
trust `copilot --help` / the linked doc over this file and open an issue.

---

## 0. Prerequisites

- Node.js ≥ 22
- `gh` CLI installed and authenticated (`gh auth status` shows a green
  check) — this repo's issue-tracker conventions
  ([`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)) assume
  `gh` throughout, and it's also Copilot CLI's auth fallback (§2)
- This repo cloned (or at minimum `agentic-workflow/ralph-copilot/`,
  `.agents/skills/`, and `Makefile`)

---

## 1. Install GitHub Copilot CLI

```bash
npm install -g @github/copilot
```

If your `~/.npmrc` sets `ignore-scripts=true`, force the postinstall step:

```bash
npm_config_ignore_scripts=false npm install -g @github/copilot
```

There's no documented `--version`-style smoke check — the first launch
itself is the check. Run it once interactively to confirm it's on `PATH`
and complete login:

```bash
copilot
> /login
```

(Source: [Install guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli))

**Unconfirmed as of writing**: whether `copilot` CLI is GA or still
preview, and which Copilot subscription tiers include CLI access — the
docs pages reachable during validation didn't state this definitively.
Confirm your plan actually covers CLI usage before wiring it into
unattended automation.

---

## 2. Authenticate non-interactively (for the loop)

Copilot CLI resolves credentials in this order:

1. `COPILOT_GITHUB_TOKEN` env var
2. `GH_TOKEN` env var
3. `GITHUB_TOKEN` env var
4. A stored OAuth token from a prior interactive `/login`
5. An authenticated `gh` CLI's token

For the ralph-copilot loop, the simplest path — matching how
`agentic-workflow/ralph/` already just relies on `gh` being authenticated —
is to **set none of the three env vars** and keep `gh auth status` green;
Copilot CLI falls back to `gh`'s token automatically.

For a scoped, purpose-built token instead: create a **fine-grained PAT**
with the **"Copilot Requests"** account permission and export it as
`COPILOT_GITHUB_TOKEN`. Classic `ghp_...` tokens are explicitly **not**
supported.

Verify either path works:

```bash
gh auth status
copilot -p "/user" -s
```

(Source: [Authenticate Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli))

---

## 3. Install Matt Pocock's engineering skills natively

Copilot CLI has its own native **Skills** system — `SKILL.md`-format,
auto-discovered from `.github/skills/`, `.claude/skills/`, or
`.agents/skills/`, invoked with `/skill-name` — separate from its
`.agent.md` custom agents.

This repo already ships `tdd` and `code-review`, the two skills the
ralph-copilot loop depends on, in `.agents/skills/` (see
[#7](https://github.com/ekoepplin/dbt-data-contract-workflow/issues/7)), so
the loop needs no install step. For the rest of the set (`grilling`,
`domain-modeling`, `to-spec`, `to-tickets`, …), use the project's installer,
which targets Copilot CLI directly:

```bash
npx skills@latest add mattpocock/skills
```

Pick **GitHub Copilot CLI** as the target agent. These extra skills are
independent of the loop. Re-run `npx skills update` later to pull
upstream changes; this only runs the public installer and never modifies
the `mattpocock/skills` repo itself.

Confirm the install:

```bash
copilot
> /skills list
```

You should see `tdd` and `code-review` (plus anything else you installed)
listed. Invoke either directly with `/tdd` or `/code-review` in a
session.

(Source: [Add skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills),
[skills.sh — GitHub Copilot target](https://www.skills.sh/agent/github-copilot))

---

## 4. Run the ralph-copilot loop

Usage mirrors `agentic-workflow/ralph/`:

```bash
agentic-workflow/ralph-copilot/afk.sh <issue-number> [max-iters]
```

`afk.sh` polls the issue and calls `once.sh` up to `max-iters` (default
10) times until it closes; `once.sh` builds a prompt from the live issue
body + `prompt.md` and drives `copilot -p` non-interactively against it,
with `--allow-tool`/`--deny-tool` flags scoped to the commands the loop needs.

`once.sh` refuses any issue that isn't open, written by the repo owner, and
labelled `ready-for-agent`, because this repo is public and the issue body
becomes the prompt.

**Run it only in a devcontainer or other disposable environment.** The loop
pushes directly to `master` and can run `make` targets against code it just
edited. A GitHub ruleset blocks force-pushes to `master`, since the `--deny-tool`
flags only match exact spellings.

To pick a model from Copilot's hosted catalog instead of Copilot's default:

```bash
agentic-workflow/ralph-copilot/once.sh <issue-number> --model claude-sonnet-4.5
```

Setting a default model in a config file is tracked by
[#9](https://github.com/ekoepplin/dbt-data-contract-workflow/issues/9).

---

## 5. How this differs from the Claude Code setup (`agentic-workflow/ralph/`)

| | Claude Code (`ralph/`) | Copilot CLI (`ralph-copilot/`) |
|---|---|---|
| Tool install | `npm install -g @anthropic-ai/claude-code` (or platform installer) | `npm install -g @github/copilot` |
| Headless auth | `ANTHROPIC_AUTH_TOKEN` / interactive login | `COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN` → `gh` fallback |
| Tool permissions | Committed `settings.ralph.json` (`allow` and `deny` lists) | Inline `--allow-tool`/`--deny-tool` flags — no committed permission file exists |
| Reusable skills | `mattpocock-skills` Claude Code plugin (`/tdd`, `/code-review`) | Native Copilot Skills, same `SKILL.md` format, committed in `.agents/skills/` |
| Model switching | `--backend {anthropic,vllm,ollama}`, redirects via `ANTHROPIC_BASE_URL` | `--model NAME` across Copilot's hosted catalog |
| Loop driver | `claude -p --setting-sources project --settings ... --permission-mode acceptEdits --model ...` | `copilot -p "..." --allow-tool=... --deny-tool=...` |

---

## 6. Command reference

| Command | Purpose |
|---|---|
| `npm install -g @github/copilot` | Install Copilot CLI |
| `copilot` then `/login` | First-run interactive auth |
| `copilot -p "<prompt>" -s` | Non-interactive: run one prompt to completion, silent metadata |
| `copilot -p "<prompt>" --no-ask-user` | Same, but never stall on a clarifying question — required for unattended loops |
| `copilot -p "<prompt>" --allow-tool='shell(git:*)' --deny-tool=...` | Scope exactly which shell commands the run may execute |
| `copilot -p "<prompt>" --model NAME` | Pin a specific model from the hosted catalog |
| `npx skills@latest add mattpocock/skills` | Install Matt Pocock's skills (pick Copilot CLI as target) |
| `npx skills update` | Refresh installed skills from upstream |
| `/skills list` | List skills Copilot CLI has discovered, inside a session |
| `gh auth status` | Confirm the `gh` fallback auth path is live |
