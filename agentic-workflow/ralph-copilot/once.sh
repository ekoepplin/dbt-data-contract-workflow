#!/bin/bash
set -euo pipefail

# Resolve locations independent of the caller's CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [--model NAME]

  --model  GitHub Copilot model name (default: Copilot's own default,
           or \$COPILOT_MODEL if set)
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
shift

MODEL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_ARGS=(--model "${2:?--model needs a value}"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "error: unknown arg: $1" >&2; usage ;;
  esac
done

REPO="ekoepplin/dbt-data-contract-workflow"

echo "ralph-copilot: issue=#$ISSUE" >&2

issue=$(gh issue view "$ISSUE" --repo "$REPO" \
  --json number,title,body,labels,state \
  --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"')
commits=$(git log -n 5 --format='%h %ad %s' --date=short)
prompt_template=$(cat "$SCRIPT_DIR/prompt.md")

prompt="MISSION: deliver issue #$ISSUE. Do NOT switch to other issues even if you see references to them.

$issue

Recent commits:
$commits

$prompt_template"

# No --allow-all-tools: every permission below is scoped to exactly what the
# loop needs. copilot -p auto-denies (rather than prompts for) anything that
# matches neither an --allow-tool nor a --deny-tool pattern, so this list is
# a real ceiling on what the unattended run can do.
#
# git/gh permission patterns match on the first-level subcommand (e.g.
# "shell(git commit)" matches any "git commit ..." invocation, args and all)
# — Copilot CLI gives no finer positional-argument scoping than that for
# allow-tool (confirmed empirically: "shell(git add -- *)" does not match
# "git add -- file.txt" the way a glob would). So dangerous *specific*
# spellings of an otherwise-needed subcommand are carved out with an exact
# literal --deny-tool instead; anything not spelled exactly that way still
# falls through to the broader allow. The non-enumerable case (STAGING
# DISCIPLINE's "only `git add -- <path>`, never `-A`/`.`") is therefore
# enforced by the prompt, not the permission layer — same trust boundary the
# Claude baseline's `Bash(git add -- *)` pattern relies on.
#
# make/uv don't get git/gh's subcommand granularity at all, so
# "shell(make:*)"/"shell(uv:*)" are the finest scoping Copilot CLI offers.
exec copilot -p "$prompt" \
  --no-ask-user \
  --allow-tool='write' \
  --allow-tool='shell(git status)' \
  --allow-tool='shell(git diff)' \
  --allow-tool='shell(git log)' \
  --allow-tool='shell(git show)' \
  --allow-tool='shell(git add)' \
  --allow-tool='shell(git reset)' \
  --allow-tool='shell(git commit)' \
  --allow-tool='shell(git push)' \
  --allow-tool='shell(gh issue view)' \
  --allow-tool='shell(gh issue comment)' \
  --allow-tool='shell(gh issue close)' \
  --allow-tool='shell(make:*)' \
  --allow-tool='shell(uv:*)' \
  --deny-tool='shell(git add -A)' \
  --deny-tool='shell(git add --all)' \
  --deny-tool='shell(git add .)' \
  --deny-tool='shell(git reset --hard)' \
  --deny-tool='shell(git push --force)' \
  --deny-tool='shell(git push -f)' \
  "${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"}"
