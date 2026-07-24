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
#   4. PR-gate backlog: merges / branch-cleanups already sitting in the gate
#      awaiting approval (gate STATE only, no GitHub), so a green PR whose "ready
#      to merge" message was missed resurfaces here instead of only on the gate's
#      24h re-ask. Snapshot-deduped — surfaced once per change, not every beat.
#
# Output contract for the heartbeat: if the last line is NO_CHANGE, reply
# HEARTBEAT_OK and stop. If it is CHANGED, summarize the ATTENTION/BLOCKED lines
# for the operator. This script never modifies project artifacts.
#
# ACTION lines: any finding with a genuine one-tap next step is followed by
#   ACTION: <label><TAB><slash-command>
# The heartbeat attaches exactly these as chat buttons on the message it posts,
# verbatim and in order, and adds none of its own. Findings only the operator can
# resolve (a missing north star, an un-run experiment) carry no ACTION line by
# design — offering a button that no skill handles is worse than offering none.
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
  # ACTION lines: a finding that has a real one-tap next step emits
  #   ACTION: <label><TAB><slash-command>
  # directly beneath it. The heartbeat attaches exactly those as chat buttons and
  # invents none of its own — a button whose command no skill handles is worse
  # than no button, because a tap that does nothing reads as a broken system.
  # Only findings the operator can actually act on from a phone get one; a
  # missing north star or an un-run experiment has no command, so it stays text.
  emit_action() { printf 'ACTION: %s\t%s\n' "$1" "$2"; }

  # A pending packet is identified on disk by its long OSR id, but the buttons
  # must carry the short handle: Telegram caps callback_data at 64 bytes and the
  # full id would overflow it, silently dropping the button.
  handle_for() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, os, pathlib, sys
state = pathlib.Path(os.environ.get(
    "RDD_RESEARCH_STATE", pathlib.Path.home() / ".local/state/edge-rdd/research")) / "state.json"
try:
    packets = json.loads(state.read_text()).get("packets", {})
except Exception:
    raise SystemExit(0)
print(packets.get(sys.argv[1], {}).get("handle", ""))
PY
  }

  if [ -d "$XFER/assignments" ]; then
    while IFS= read -r f; do
      echo "ATTENTION: assignment older than 2h never produced a packet (dispatch died?): $(basename "$f")"
      emit_action "📋 Show the research queue" "/research list"
    done < <(find "$XFER/assignments" -name 'ERA-*.md' -mmin +120 2>/dev/null)
  fi
  if [ -d "$XFER/incoming" ]; then
    while IFS= read -r f; do
      osr="$(basename "$f" .md)"
      echo "ATTENTION: packet pending operator Accept/Reject for >24h: $osr"
      h="$(handle_for "$osr")"
      if [ -n "$h" ]; then
        emit_action "📄 Read the waiting packet" "/research show $h"
        emit_action "✅ Accept it into the knowledge base" "/research accept $h"
        emit_action "❌ Reject it" "/research reject $h"
      fi
    done < <(find "$XFER/incoming" -name 'OSR-*.md' -mmin +1440 2>/dev/null)
  fi

  # --- 3. OpenScience health -----------------------------------------------------
  if ! curl -sf -m 8 -o /dev/null "${RDD_RESEARCH_OS_BASE:-http://127.0.0.1:3457}/session"; then
    echo "ATTENTION: OpenScience server is DOWN"
    emit_action "🩺 Check the research service" "/research status"
  fi

  # --- 4. gate merge backlog ------------------------------------------------------
  # Surface merges / branch-cleanups already sitting in the PR gate awaiting your
  # approval, so a green PR whose "ready to merge" chat message was missed —
  # gateway restart, CI-watcher timeout, a dropped notification — resurfaces on the
  # next heartbeat instead of only when the gate re-asks (RDD_GATE_REASK_HOURS,
  # default 24h). Reads the gate's STATE ONLY (no GitHub calls, no re-posting), so
  # it is cheap and survives restarts; the sweep snapshot de-dups so a stable
  # backlog is surfaced once, not every beat (the 2026-07-14 heartbeat-spam lesson).
  # This is a nudge, never the approval surface — acting still goes through the
  # gate, which re-verifies every gate at the moment you tap.
  GATE_STATE="${RDD_GATE_STATE_DIR:-$HOME/.local/state/edge-rdd/pr-gate}/state.json"
  n_gate="$(python3 - "$GATE_STATE" <<'PY' 2>/dev/null
import json, sys
try:
    actions = json.load(open(sys.argv[1])).get("actions", {})
except Exception:
    print(0); raise SystemExit
# Same filter as edge-pr-gate.sh's `pending`: every pending action a human can
# approve (merge / prune / destructive delete), excluding the snooze/batch
# control pseudo-actions.
print(sum(1 for a in actions.values()
          if a.get("status") == "pending" and a.get("kind") not in ("snooze", "batch")))
PY
)"
  if [ "${n_gate:-0}" -gt 0 ]; then
    echo "ATTENTION: $n_gate gate action(s) awaiting your approval (green PR merges / branch cleanups) — held in the gate, nothing acts without your tap"
    emit_action "🚦 Review the gate queue" "/gate sweep"
  fi
)"

echo "$OUT"
# ACTION lines are button specs, not findings — never count them as issues.
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
