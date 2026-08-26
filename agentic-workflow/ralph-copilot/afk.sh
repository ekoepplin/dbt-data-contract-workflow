#!/bin/bash
set -eo pipefail

# Resolve locations independent of the caller's CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [max-iters] [--model NAME]

  max-iters  default: 10
  --model    GitHub Copilot model name (forwarded to once.sh)
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
shift

MAX=10
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
  MAX="$1"
  shift
fi

REPO="ekoepplin/dbt-data-contract-workflow"

for ((i=1; i<=MAX; i++)); do
  state=$(gh issue view "$ISSUE" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo UNKNOWN)
  if [[ "$state" == "CLOSED" ]]; then
    echo "Issue #$ISSUE is CLOSED — done in $((i-1)) iters."
    exit 0
  fi
  echo "=== iter $i/$MAX on #$ISSUE (state=$state) ==="
  "$SCRIPT_DIR/once.sh" "$ISSUE" "$@"
  echo "=== iter $i complete ==="
done

echo "Hit MAX=$MAX iters on #$ISSUE without closing. Inspect and resume manually."
exit 1
