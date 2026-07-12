#!/usr/bin/env bash
# openscience-research.sh — EDGE ⇄ OpenScience research dispatch (thin wrapper).
#
# Sources ~/.config/edge-rdd/research.env, then:
#   assign "<question>" [--project P] [--context "…"]
#        → writes the assignment, DETACHES an async dispatch (returns immediately,
#          the packet + approval buttons post to the assignment return thread when ready),
#   everything else (dispatch/list/show/accept/reject/followup/status/health)
#        → delegated synchronously to openscience-research.py.
#
# Mirrors edge-coder-run.sh's async-dispatch UX and edge-pr-gate.sh's config
# discipline (a ~/.config/edge-rdd/*.env file with NO RDD_REPO_DIR, so the PR
# gate's project sweep correctly ignores it).
set -uo pipefail

CFG="${RDD_RESEARCH_CONFIG:-$HOME/.config/edge-rdd/research.env}"
if [ -f "$CFG" ]; then set -a; . "$CFG"; set +a; fi
# openclaw CLI often lives outside a systemd-spawned PATH (gateway exec).
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

PY="$HOME/.openclaw/shared-scripts/openscience-research.py"
LOGDIR="${RDD_RESEARCH_STATE:-$HOME/.local/state/edge-rdd/research}"
mkdir -p "$LOGDIR"

verb="${1:-}"
shift 2>/dev/null || true

case "$verb" in
  assign|followup)
    # Report the actual return thread if the caller supplied --thread; otherwise
    # fall back to the configured default/home research thread.
    return_thread="${RDD_RESEARCH_TG_THREAD:-?}"
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--thread" ]; then
        return_thread="$(printf '%s' "$arg" | tr -cd '0-9')"
        [ -n "$return_thread" ] || return_thread="${RDD_RESEARCH_TG_THREAD:-?}"
        break
      fi
      prev="$arg"
    done
    era="$(python3 "$PY" "$verb" "$@")" || exit $?
    [ -z "$era" ] && { echo "$verb failed" >&2; exit 1; }
    setsid bash -c 'exec python3 "$1" dispatch "$2"' _ "$PY" "$era" \
        >>"$LOGDIR/research.log" 2>&1 </dev/null &
    echo "DISPATCHED $era — packet will post to topic $return_thread when ready"
    ;;
  "")
    echo "usage: openscience-research.sh {assign|dispatch|list|show|accept|reject|followup|status|health}" >&2
    exit 2
    ;;
  *)
    exec python3 "$PY" "$verb" "$@"
    ;;
esac
