#!/usr/bin/env bash
# rdd-heartbeat-sweep.sh — deterministic RDD integrity sweep for the heartbeat.
#
# Replaces the prose instruction "run the validator for each notes dir" with one
# command the heartbeat executes verbatim. Covers:
#   1. Superior Architecture validation per project. Projects are discovered as
#      workspace projects/<slug>/ dirs containing a PROJECT.md (pseudo-dirs like
#      the research mailbox are skipped), or set RDD_SWEEP_PROJECTS="slug[:arch-path] …"
#      to pin the list and any non-default artifact locations explicitly.
#      Also nags when research notes are newer than the project's last
#      Superior Architecture synthesis (evidence not yet folded in).
#   2. Research-loop hygiene: stale un-dispatched assignments (a successful
#      dispatch archives its assignment, so anything old here means a dispatch
#      died silently) and packets pending operator Accept/Reject for >24h.
#   3. OpenScience reachability.
#
# Output contract for the heartbeat: if the last line is NO_CHANGE, reply
# HEARTBEAT_OK and stop. If it is CHANGED, summarize the ATTENTION/BLOCKED lines
# for the operator. This script never modifies project artifacts.
set -uo pipefail

WS="${RDD_WORKSPACE:-$HOME/.openclaw/workspace-edge}"
STATED="$HOME/.local/state/edge-rdd"
SNAP="$STATED/arch-sweep.last"
LOG="$STATED/arch-sweep.log"
XFER="${RDD_RESEARCH_XFER:-$WS/projects/edge-research-transfer}"
mkdir -p "$STATED"

OUT="$(
  cd "$WS" || exit 1

  # --- 1. architecture validation ---------------------------------------------
  run_validator() {
    local slug="$1"; shift
    echo "=== $slug ==="
    python3 scripts/validate-superior-architecture.py \
      --workspace . --project "$slug" --heartbeat "$@" 2>&1
    echo "--- $slug rc=$? ---"
  }
  # A note or accepted packet whose mtime post-dates the Superior Architecture
  # artifact is evidence not yet folded in. The validator can't see unbound
  # files; this nag closes that hole. A synthesis pass rewrites the artifact,
  # which clears the nag naturally. (mtime is a nag signal, not proof — restores
  # can produce transient noise; fold in or touch the artifact after judging.)
  research_newer_than_synthesis() {
    local slug="$1" arch="$2"
    [ -f "$arch" ] || return 0
    while IFS= read -r f; do
      echo "ATTENTION: $slug research newer than Superior Architecture synthesis: $(basename "$f") — fold in and re-bind"
    done < <(find "projects/$slug/notes" -maxdepth 1 -name '*.md' ! -name 'SUPERIOR_ARCHITECTURE.md' -newer "$arch" 2>/dev/null | sort)
  }
  sweep_project() {
    local slug="$1" arch="${2:-}"
    if [ -n "$arch" ]; then
      run_validator "$slug" --architecture-path "$arch"
    else
      arch="projects/$slug/notes/SUPERIOR_ARCHITECTURE.md"
      run_validator "$slug"
    fi
    research_newer_than_synthesis "$slug" "$arch"
  }
  if [ -n "${RDD_SWEEP_PROJECTS:-}" ]; then
    for entry in $RDD_SWEEP_PROJECTS; do
      slug="${entry%%:*}"; arch="${entry#*:}"
      [ "$arch" = "$entry" ] && arch=""
      sweep_project "$slug" "$arch"
    done
  else
    for d in projects/*/; do
      [ -f "$d/PROJECT.md" ] || continue
      sweep_project "$(basename "$d")"
    done
  fi

  # --- 2. research-loop hygiene ------------------------------------------------
  if [ -d "$XFER/assignments" ]; then
    while IFS= read -r f; do
      echo "ATTENTION: assignment older than 2h never produced a packet (dispatch died?): $(basename "$f")"
    done < <(find "$XFER/assignments" -name 'ERA-*.md' -mmin +120 2>/dev/null)
  fi
  if [ -d "$XFER/incoming" ]; then
    while IFS= read -r f; do
      echo "ATTENTION: packet pending operator Accept/Reject for >24h: $(basename "$f" .md)"
    done < <(find "$XFER/incoming" -name 'OSR-*.md' -mmin +1440 2>/dev/null)
  fi

  # --- 3. OpenScience health -----------------------------------------------------
  if ! curl -sf -m 8 -o /dev/null "${RDD_RESEARCH_OS_BASE:-http://127.0.0.1:3457}/session"; then
    echo "ATTENTION: OpenScience server is DOWN"
  fi
)"

echo "$OUT"
n_issues=$(printf '%s\n' "$OUT" | grep -Ec '^(BLOCKED|ATTENTION)') || true
if [ -f "$SNAP" ] && [ "$OUT" = "$(cat "$SNAP")" ]; then
  echo "NO_CHANGE"
  verdict=NO_CHANGE
else
  printf '%s\n' "$OUT" > "$SNAP"
  echo "CHANGED"
  verdict=CHANGED
fi
printf '%s SWEEP %s issues=%s\n' "$(date -Is)" "$verdict" "$n_issues" >> "$LOG"
