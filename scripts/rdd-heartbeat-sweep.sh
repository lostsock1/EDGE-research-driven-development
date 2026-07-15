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
  # Surface experiment candidates. A project's Superior Architecture "## Open
  # frontier" section is where the research agent records discriminating questions
  # it judged worth a contained lab experiment (persona: "spark targets worth a
  # contained experiment"). Emit one SUGGEST per real open item so it does not
  # sit un-tested. This NEVER runs anything. A listed item = still open; the item
  # is removed once the lab result is folded in, and the sweep-level snapshot
  # de-dups between beats so a standing suggestion is posted once, not every beat.
  experiment_candidates() {
    local slug="$1" arch="$2"
    [ -f "$arch" ] || return 0
    local relarch="${arch#./}"
    awk '
      function flush(   lbl) {
        if (item == "") return
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
        if (item ~ /[A-Za-z0-9]/ && item != "…") {
          lbl = item
          if (match(lbl, /^\*\*[^*]+\*\*/)) { lbl = substr(lbl, 1, RLENGTH) }
          else if (match(lbl, /\. /))       { lbl = substr(lbl, 1, RSTART) }
          gsub(/\*/, "", lbl)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", lbl)
          if (length(lbl) > 160) lbl = substr(lbl, 1, 157) "..."
          print lbl
        }
        item = ""
      }
      /^##[[:space:]]+Open frontier/ { insec=1; next }
      /^##[[:space:]]/               { if (insec) flush(); insec=0; next }
      !insec { next }
      /^[[:space:]]*-[[:space:]]+/ { flush(); item=$0; sub(/^[[:space:]]*-[[:space:]]+/, "", item); next }
      /^[[:space:]]*$/             { flush(); next }
      /^[[:space:]]*(---+|\*\*\*+|<!--)/ { flush(); next }
      item != "" { c=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, " ", c); item=item c; next }
      END { flush() }
    ' "$arch" | while IFS= read -r label; do
      echo "SUGGEST: $slug — experiment worth running: ${label} (see ${relarch} '## Open frontier'; pre-register + run: lab/lab-run.sh --new <slug>)"
    done
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
    experiment_candidates "$slug" "$arch"
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
n_issues=$(printf '%s\n' "$OUT" | grep -Ec '^(BLOCKED|ATTENTION|SUGGEST)') || true
if [ -f "$SNAP" ] && [ "$OUT" = "$(cat "$SNAP")" ]; then
  echo "NO_CHANGE"
  verdict=NO_CHANGE
else
  printf '%s\n' "$OUT" > "$SNAP"
  echo "CHANGED"
  verdict=CHANGED
fi
printf '%s SWEEP %s issues=%s\n' "$(date -Is)" "$verdict" "$n_issues" >> "$LOG"
