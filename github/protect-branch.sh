#!/usr/bin/env bash
# protect-branch.sh — apply the EDGE branch-protection posture to the trunk.
#
# The human merge gate is MECHANICAL, not behavioral: agents cannot push to the
# trunk even if a prompt goes wrong, because GitHub rejects it. PRs require
# green required checks + an up-to-date branch; 0 approvals (the operator IS
# the merge button); no force pushes; no deletions; admins included.
#
# Usage:
#   OWNER=you REPO=yourrepo BRANCH=main CHECKS="tests,lint" ./protect-branch.sh
# Or with ~/.config/edge-rdd/config.env present, just: ./protect-branch.sh
#
# Requires: gh (authed with admin on the repo), python3.

set -euo pipefail

CONFIG="${EDGE_RDD_CONFIG:-$HOME/.config/edge-rdd/config.env}"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

OWNER="${OWNER:-${RDD_REPO_SLUG%%/*}}"
REPO="${REPO:-${RDD_REPO_SLUG##*/}}"
BRANCH="${BRANCH:-${RDD_MAIN_BRANCH:-main}}"
if [[ -v CHECKS ]]; then
  CHECKS_VALUE="$CHECKS"
elif [[ -v RDD_REQUIRED_CHECKS ]]; then
  CHECKS_VALUE="$RDD_REQUIRED_CHECKS"
else
  CHECKS_VALUE="tests,lint"
fi

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  echo "protect-branch: set OWNER/REPO (or RDD_REPO_SLUG in config.env)" >&2
  exit 2
fi

# Build the contexts JSON array from the comma-separated list, trimming spaces.
CONTEXTS_JSON="$(python3 - "$CHECKS_VALUE" <<'PY'
import json, sys
print(json.dumps([c.strip() for c in sys.argv[1].split(",") if c.strip()]))
PY
)"

echo "Protecting $OWNER/$REPO@$BRANCH with required checks: $CONTEXTS_JSON"

gh api -X PUT "repos/$OWNER/$REPO/branches/$BRANCH/protection" --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CONTEXTS_JSON
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

ACTUAL_JSON="$(gh api "repos/$OWNER/$REPO/branches/$BRANCH/protection" \
  --jq '.required_status_checks.contexts | sort')"
EXPECTED_JSON="$(python3 - "$CONTEXTS_JSON" <<'PY'
import json, sys
print(json.dumps(sorted(json.loads(sys.argv[1])), separators=(",", ":")))
PY
)"
ACTUAL_COMPACT="$(python3 - "$ACTUAL_JSON" <<'PY'
import json, sys
print(json.dumps(json.loads(sys.argv[1]), separators=(",", ":")))
PY
)"
if [ "$ACTUAL_COMPACT" != "$EXPECTED_JSON" ]; then
  echo "protect-branch: verification failed: expected $EXPECTED_JSON, got $ACTUAL_COMPACT" >&2
  exit 1
fi
echo "Done. Verified required checks: $ACTUAL_COMPACT"
