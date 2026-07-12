#!/usr/bin/env bash
# openscience-smoke.sh — verify EDGE ⇄ OpenScience research plumbing.
# Default runs the full isolated dispatch smoke. Use --health-only to avoid model/API use.
set -euo pipefail

MODE="full"
if [ "${1:-}" = "--health-only" ]; then
  MODE="health"
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "usage: openscience-smoke.sh [--health-only]"
  exit 0
fi

PY="$HOME/.openclaw/shared-scripts/openscience-research.py"
BASE="${RDD_RESEARCH_OS_BASE:-http://127.0.0.1:3457}"
CONFIG="$HOME/.config/openscience/openscience.json"
ENVFILE="$HOME/.config/openscience/openscience.env"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -r "$CONFIG" ] || fail "OpenScience config is not readable: $CONFIG"
[ -r "$ENVFILE" ] || fail "OpenScience env file is not readable: $ENVFILE"

config_real="$(readlink -f "$CONFIG")"
env_real="$(readlink -f "$ENVFILE")"
case "$config_real" in "$HOME/.openclaw"/*) fail "config resolves into sandbox-inaccessible ~/.openclaw: $config_real";; esac
case "$env_real" in "$HOME/.openclaw"/*) fail "env resolves into sandbox-inaccessible ~/.openclaw: $env_real";; esac
pass "config/env readable and outside ~/.openclaw sandbox"

systemctl --user --quiet is-active openscience.service || fail "openscience.service is not active"
pass "openscience.service is active"

curl -fsS --max-time 8 "$BASE/session" >/dev/null || fail "OpenScience API GET /session failed at $BASE"
pass "OpenScience API responds to GET /session"

bash "$HOME/.openclaw/shared-scripts/openscience-research.sh" health >/dev/null || fail "openscience-research.sh health failed"
pass "research driver health check passes"

if [ "$MODE" = "health" ]; then
  exit 0
fi

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

export RDD_RESEARCH_XFER="$tmp/xfer"
export RDD_RESEARCH_KB="$tmp/kb"
export RDD_RESEARCH_STATE="$tmp/state"
export RDD_RESEARCH_TG_TARGET=""
export RDD_RESEARCH_TG_THREAD=""
export RDD_RESEARCH_OS_BASE="$BASE"
export RDD_RESEARCH_AGENT="${RDD_RESEARCH_AGENT:-research}"
export RDD_RESEARCH_TIMEOUT="${RDD_RESEARCH_TIMEOUT:-1200}"

question="Smoke test: in one short sentence, what does BM25 rank?"
era="$(python3 "$PY" assign "$question" --project smoke)"
[ -n "$era" ] || fail "assignment did not return an ERA id"
pass "assignment created: $era"

python3 "$PY" dispatch "$era" >/dev/null
packet_json="$(find "$RDD_RESEARCH_XFER/incoming" -maxdepth 1 -name 'OSR-*.json' -print -quit)"
[ -n "$packet_json" ] || fail "dispatch did not produce an incoming OSR packet"
python3 - "$packet_json" "$era" <<'PY'
import json, sys
packet = json.load(open(sys.argv[1]))
expected = sys.argv[2]
assert packet["assignment_id"] == expected, (packet["assignment_id"], expected)
assert packet["status"] == "candidate", packet["status"]
assert packet["profile"] == "software", packet.get("profile")
assert packet["implementation_allowed"] is False
assert packet["requires_user_approval"] is True
print(packet["packet_id"])
PY
pass "isolated full dispatch produced an approval-gated incoming packet"
