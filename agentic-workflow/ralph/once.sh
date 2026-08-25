#!/bin/bash
set -euo pipefail

# Resolve locations independent of the caller's CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Source environment
if [[ -f .env.ralph ]]; then
  set -a
  source .env.ralph
  set +a
fi

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [--backend NAME] [--model NAME]

  --backend  one of: anthropic | vllm | ollama
             default: \$RALPH_BACKEND, else 'vllm'
  --model    model name for the chosen backend
             default: \$RALPH_MODEL, else backend default
               anthropic -> sonnet
               vllm      -> \$VLLM_DEFAULT_MODEL
               ollama    -> \$OLLAMA_DEFAULT_MODEL
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
shift

BACKEND="${RALPH_BACKEND:-vllm}"
MODEL="${RALPH_MODEL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKEND="${2:?--backend needs a value}"; shift 2 ;;
    --model)   MODEL="${2:?--model needs a value}";     shift 2 ;;
    -h|--help) usage ;;
    *) echo "error: unknown arg: $1" >&2; usage ;;
  esac
done

case "$BACKEND" in
  anthropic)
    unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    : "${MODEL:=sonnet}"
    ;;
  vllm)
    export ANTHROPIC_AUTH_TOKEN=vllm
    export ANTHROPIC_BASE_URL=http://host.docker.internal:8000
    : "${MODEL:=${VLLM_DEFAULT_MODEL:-qwen}}"
    ;;
  ollama)
    export ANTHROPIC_AUTH_TOKEN=ollama
    export ANTHROPIC_BASE_URL=http://host.docker.internal:11434
    : "${MODEL:=${OLLAMA_DEFAULT_MODEL:-qwen3.5:4b}}"
    ;;
  *)
    echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2
    exit 1
    ;;
esac

CLAUDE_SETTINGS="$SCRIPT_DIR/settings.ralph.json"
REPO="ekoepplin/dbt-data-contract-workflow"

echo "ralph: backend=$BACKEND model=$MODEL issue=#$ISSUE" >&2

issue=$(gh issue view "$ISSUE" --repo "$REPO" \
  --json number,title,body,labels,state \
  --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"')
commits=$(git log -n 5 --format='%h %ad %s' --date=short)
prompt=$(cat "$SCRIPT_DIR/prompt.md")

claude --settings "$CLAUDE_SETTINGS" --permission-mode acceptEdits --model "$MODEL" \
  "MISSION: deliver issue #$ISSUE. Do NOT switch to other issues even if you see references to them.

$issue

Recent commits:
$commits

$prompt"
