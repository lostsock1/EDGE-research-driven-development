#!/usr/bin/env bash
# edge-coder-run.sh — EDGE → coder dispatch with EDGE-owned ordered model
# fallback, automatic feedback-loop closure, async completion push, and CI watching.
#
# Part of the "EDGE — Research Driven Development" template.
#
# MODES
#   default (async):  validates, takes the repo lock, detaches a worker, and returns
#                     immediately with "DISPATCHED <run-id>". The worker runs the
#                     coder, then POSTS the completion summary (model, branch,
#                     commits, PR, trailer status) to the project chat thread, and
#                     keeps watching the PR's CI checks, posting the green/red
#                     verdict when they finish. The dispatching agent's exec
#                     returns in ~1s.
#   --fg:             foreground mode — blocks and prints everything to stdout
#                     (debugging / operator use). CI watcher still runs detached.
#                     Foreground uses shorter per-tier timeouts so the worst case
#                     stays inside the dispatching agent's exec-timeout budget.
#   status:           show lock holder + recent runs.
#
# CONFIGURATION — layered at startup:
#   ~/.config/edge-rdd/config.env (shared model/timeout/variant policy), then
#   $EDGE_RDD_CONFIG or RDD_DEFAULT_PROJECT_CONFIG (project identity overlay).
# See template.env.example in the template repo for every knob.
#
# MODEL FALLBACK: opencode has NO native retry-on-429 and NO provider fallback —
# this wrapper's ordered tier ladder IS the fallback layer. RDD_MODELS /
# RDD_TIMEOUTS_* are the single source of truth for the order; do not restate
# the order in prose docs (it drifts). RDD_VARIANT_POLICY=auto can choose
# per-tier OpenCode variants from task difficulty; explicit override via
# EDGE_CODER_EFFORT=<fast|standard|deep|max> or a task prefix [effort=deep].
#
# Failure = nonzero exit OR {"type":"error"} stream event OR no text produced.
# A permission block or a normal completion is NOT a failure.
#
# PR FLOW (required once the trunk is branch-protected): the coder works on a
# <prefix>/* branch and opens a PR to the trunk; direct pushes are rejected by
# GitHub. The dispatch protocol (SUFFIX below) instructs this and the trailer
# carries PR:.
#
# Reliability:
#   - $HOME/.git guard: a stray git repo at $HOME makes opencode snapshot-walk
#     the whole home dir and hang forever — refuse to dispatch if present.
#   - Concurrency lock (flock, one per repo tree) with holder info: a second
#     concurrent dispatch is refused (exit 3) and told who holds the lock.
#   - Per-tier liveness probe with its own timeout (index-aligned with
#     RDD_MODELS), then a fixed work budget for the real task.
#   - Partial-work handoff: if a failed tier left commits or a dirty tree, the
#     next tier is told to inspect and CONTINUE, not restart.
#   - Failure classification: each failed tier is labeled (rate-limited,
#     quota/billing, auth, provider-overloaded, hard-timeout, …) in the ledger
#     and in the chat messages, so a silent fallback never hides the reason.
#   - Trailer verification: output missing the '=== LOOP STATUS ===' trailer is
#     flagged (model-adherence failure) instead of silently accepted.
#   - Permissions stay ON — never --dangerously-skip-permissions.
#
# Usage:  edge-coder-run.sh [--dir <repo_root>] [--fg] '<promoted implementation task>'
#         edge-coder-run.sh status
# Log:    $RDD_LOG                (dispatch ledger)
#         $RDD_RUNS_DIR/<id>.log  (full per-run output)

set -uo pipefail
# Source OpenClaw .env so provider API keys reach opencode.
[ -f "$HOME/.openclaw/.env" ] && source "$HOME/.openclaw/.env"

# ---- configuration --------------------------------------------------------
# config.env owns shared runtime policy (models/timeouts/variants). A selected
# per-project file overlays project identity only. Clear identity between the
# two sources so an incomplete project file cannot silently dispatch the
# primary project from config.env.
SHARED_CONFIG="${RDD_SHARED_CONFIG:-$HOME/.config/edge-rdd/config.env}"
# shellcheck disable=SC1090
[ -f "$SHARED_CONFIG" ] && . "$SHARED_CONFIG"
CONFIG="${EDGE_RDD_CONFIG:-${RDD_DEFAULT_PROJECT_CONFIG:-$SHARED_CONFIG}}"
if [ "$CONFIG" != "$SHARED_CONFIG" ]; then
  unset RDD_REPO_DIR RDD_REPO_SLUG RDD_PROJECT_NAME RDD_PROJECT_SLUG \
    RDD_MAIN_BRANCH RDD_BRANCH_PREFIX RDD_DOCS_DIR RDD_TG_CHANNEL \
    RDD_TG_TARGET RDD_TG_THREAD RDD_REQUIRED_CHECKS
  # shellcheck disable=SC1090
  [ -f "$CONFIG" ] && . "$CONFIG"
fi

OPENCODE=${EDGE_CODER_OPENCODE:-${RDD_OPENCODE:-$HOME/.opencode/bin/opencode}}
OCLI=${RDD_OPENCLAW:-$HOME/.local/bin/openclaw}
DIR=${RDD_REPO_DIR:-$HOME/projects/myproject}
AGENT=${RDD_AGENT:-code-monkeys/coder}
MAIN_BRANCH=${RDD_MAIN_BRANCH:-main}
BRANCH_PREFIX=${RDD_BRANCH_PREFIX:-cm}
DOCS_DIR=${RDD_DOCS_DIR:-docs/agent}
# RDD_MODELS is the ordered tier ladder — no built-in default on purpose:
# the model choice belongs to the operator's config, not this script.
read -r -a MODELS      <<< "${RDD_MODELS:-}"
read -r -a VARIANTS    <<< "${RDD_VARIANTS:-}"
# RDD_TIMEOUTS_* bound the per-tier LIVENESS PROBE, index-aligned with
# RDD_MODELS. The real task gets WORK_TO (below) once a tier answers its probe.
read -r -a TIMEOUTS_BG <<< "${RDD_TIMEOUTS_BG:-60 60}"
read -r -a TIMEOUTS_FG <<< "${RDD_TIMEOUTS_FG:-60 60}"
VARIANT_POLICY=${RDD_VARIANT_POLICY:-static}
EFFORT_PROFILE=${EDGE_CODER_EFFORT_PROFILE:-}
LOG=${RDD_LOG:-$HOME/.local/state/edge-rdd/edge-coder-run.log}
RUNS_DIR=${RDD_RUNS_DIR:-$HOME/.local/state/edge-rdd/runs}
LOCKDIR=${RDD_LOCKDIR:-$HOME/.local/state/edge-rdd/locks}
NUDGE_CHANNEL=${RDD_TG_CHANNEL:-telegram}
NUDGE_TARGET=${EDGE_CODER_TARGET:-${RDD_TG_TARGET:-}}
NUDGE_THREAD=${EDGE_CODER_THREAD:-${RDD_TG_THREAD:-}}
CI_POLL_SECS=${RDD_CI_POLL_SECS:-60}
CI_POLL_MAX=${RDD_CI_POLL_MAX:-40}
GATE_SCRIPT=${RDD_GATE_SCRIPT:-$HOME/.openclaw/shared-scripts/edge-pr-gate.sh}
# gh/setsid/flock often live outside a systemd-spawned PATH — prepend what you need.
[ -n "${RDD_PATH_PREPEND:-}" ] && export PATH="$RDD_PATH_PREPEND:$PATH"

ts() { date +%Y-%m-%dT%H:%M:%S%z; }
mkdir -p "$(dirname "$LOG")" "$RUNS_DIR" "$LOCKDIR"
# Cleanup rotated stream logs older than 7 days
find "$RUNS_DIR" -name "stream.log.old" -mtime +7 -delete 2>/dev/null || true

# ---- dependency preflight ---------------------------------------------------
for c in flock setsid timeout git python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "edge-coder-run: missing required tool: $c" >&2; exit 2; }
done
HAVE_GH=1
{ command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; } || {
  HAVE_GH=0
  echo "[$(ts)] WARN gh/jq not found — PR lookup and CI watching disabled" >> "$LOG"
}

send_tg() { # send_tg "<message>"  (best-effort; EDGE_CODER_DRYRUN_MSG=1 prints instead)
  local msg="$1"
  if [ "${EDGE_CODER_DRYRUN_MSG:-0}" = "1" ]; then
    printf 'DRYRUN-TG >>>\n%s\n<<< DRYRUN-TG\n' "$msg"
    return 0
  fi
  if [ -z "$NUDGE_TARGET" ]; then
    echo "[$(ts)] NOTE no chat target configured (RDD_TG_TARGET) — message not sent" >> "$LOG"
    return 0
  fi
  local -a thread_args=()
  [ -n "$NUDGE_THREAD" ] && thread_args=(--thread-id "$NUDGE_THREAD")
  timeout 60 "$OCLI" message send --channel "$NUDGE_CHANNEL" --target "$NUDGE_TARGET" \
    "${thread_args[@]}" --message "$msg" >>"$LOG" 2>&1
}

# ---- arg parsing ------------------------------------------------------------
MODE=bg
WORKER=0
RUN_ID=""
if [ "${1:-}" = "status" ]; then
  echo "=== edge-coder-run status ==="
  for h in "$LOCKDIR"/edge-coder-*.lock.holder; do
    [ -f "$h" ] || continue
    lock="${h%.holder}"
    if exec 8>"$lock" 2>/dev/null && flock -n 8; then
      echo "lock FREE: $(basename "$lock")"; flock -u 8
    else
      echo "lock HELD: $(basename "$lock") — $(cat "$h" 2>/dev/null)"
    fi
    exec 8>&- 2>/dev/null || true
  done
  echo "--- recent runs ---"
  ls -t "$RUNS_DIR" 2>/dev/null | head -5 | while read -r f; do
    printf '%s  (%s bytes)\n' "$f" "$(stat -c%s "$RUNS_DIR/$f" 2>/dev/null)"
  done
  echo "--- ledger tail ---"
  tail -5 "$LOG" 2>/dev/null
  exit 0
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    DIR="$2"; shift 2 ;;
    --fg)     MODE=fg; shift ;;
    --worker) WORKER=1; RUN_ID="$2"; shift 2 ;;
    *)        break ;;
  esac
done
TASK="${1:-}"
if [ -z "$TASK" ]; then
  echo "usage: edge-coder-run.sh [--dir <repo_root>] [--fg] '<task>'  |  status" >&2
  exit 2
fi

# ---- effort / variant policy --------------------------------------------------
strip_effort_prefix() {
  local raw="$1"
  if [[ "$raw" =~ ^[[:space:]]*\[effort=(fast|standard|deep|max|auto|static)\][[:space:]]*(.*)$ ]]; then
    TASK_EFFORT_PREFIX="${BASH_REMATCH[1]}"
    TASK="${BASH_REMATCH[2]}"
  else
    TASK_EFFORT_PREFIX=""
    TASK="$raw"
  fi
}

classify_effort() { # classify_effort "<task>" -> fast|standard|deep|max
  local t="${1,,}" len
  len=${#1}
  if [[ "$t" =~ security|secret|credential|auth|permission|sandbox|incident|breach|exploit|data[[:space:]-]*loss|corrupt|corruption|production|prod[[:space:]-]*down|outage|payment|billing|irreversible|delete|wipe|rotate[[:space:]-]*key|emergency|rollback ]]; then
    echo max; return
  fi
  if [[ "$t" =~ root[[:space:]-]*cause|regression|refactor|migration|schema|database|performance|race|deadlock|concurrency|distributed|architecture|design|multi[[:space:]-]*file|ci[[:space:]-]*(red|fail)|test[[:space:]-]*fail|flaky|investigate|debug|diagnose|unknown|cross[[:space:]-]*system ]]; then
    echo deep; return
  fi
  if [ "$len" -le 300 ] && [[ "$t" =~ typo|spelling|copy|readme|docs?|comment|format|rename|one[[:space:]-]*line|small|trivial|lint|style ]]; then
    echo fast; return
  fi
  echo standard
}

variants_for_effort() { # variants_for_effort <fast|standard|deep|max>
  # Per-profile variant maps come from the dispatch config (RDD_VARIANTS_*),
  # index-aligned with RDD_MODELS. Every value must exist as a model variant
  # in your opencode config. An empty/unset map is valid: the profile is still
  # classified and recorded, but tiers keep the baseline RDD_VARIANTS (or none).
  case "$1" in
    fast)     echo "${RDD_VARIANTS_FAST:-}" ;;
    standard) echo "${RDD_VARIANTS_STANDARD:-}" ;;
    deep)     echo "${RDD_VARIANTS_DEEP:-}" ;;
    max)      echo "${RDD_VARIANTS_MAX:-}" ;;
    *)        return 1 ;;
  esac
}

resolve_effort_variants() {
  local prefix profile variant_line
  strip_effort_prefix "$TASK"
  prefix="${TASK_EFFORT_PREFIX:-}"
  profile="${EDGE_CODER_EFFORT:-${EFFORT_PROFILE:-}}"
  [ -z "$profile" ] && [ -n "$prefix" ] && profile="$prefix"
  if [ -z "$profile" ]; then
    if [ "$VARIANT_POLICY" = auto ]; then
      profile="$(classify_effort "$TASK")"
    else
      profile=static
    fi
  fi
  [ "$profile" = auto ] && profile="$(classify_effort "$TASK")"

  if [ "$profile" = static ]; then
    EFFORT_PROFILE=static
  elif variant_line="$(variants_for_effort "$profile")"; then
    EFFORT_PROFILE="$profile"
    if [ -n "$variant_line" ]; then
      read -r -a VARIANTS <<< "$variant_line"
      export RDD_VARIANTS="$variant_line"
    fi
  else
    echo "edge-coder-run: invalid effort profile '$profile' (use fast|standard|deep|max|auto|static)" >&2
    exit 2
  fi
  export EDGE_CODER_EFFORT_PROFILE="$EFFORT_PROFILE"
}
resolve_effort_variants

# ---- guards -------------------------------------------------------------------
if [ ${#MODELS[@]} -eq 0 ]; then
  echo "edge-coder-run: RDD_MODELS is empty — define the ordered tier ladder in $CONFIG (see template.env.example)." >&2
  exit 2
fi
if [ "$CONFIG" != "$SHARED_CONFIG" ] && [ -z "${RDD_REPO_DIR:-}" ]; then
  echo "edge-coder-run: selected project config $CONFIG has no RDD_REPO_DIR; refusing to inherit project identity from config.env" >&2
  exit 2
fi
validate_aligned() { # validate_aligned NAME allow-empty values...
  local name="$1" allow_empty="$2"; shift 2
  local count=$#
  if [ "$count" -eq 0 ] && [ "$allow_empty" = yes ]; then return 0; fi
  if [ "$count" -ne "${#MODELS[@]}" ]; then
    echo "edge-coder-run: $name has $count value(s), but RDD_MODELS has ${#MODELS[@]}; arrays must be index-aligned" >&2
    exit 2
  fi
}
validate_aligned RDD_TIMEOUTS_BG no "${TIMEOUTS_BG[@]}"
validate_aligned RDD_TIMEOUTS_FG no "${TIMEOUTS_FG[@]}"
validate_aligned RDD_VARIANTS yes "${VARIANTS[@]}"
for profile_name in FAST STANDARD DEEP MAX; do
  profile_value_var="RDD_VARIANTS_${profile_name}"
  read -r -a profile_values <<< "${!profile_value_var:-}"
  validate_aligned "$profile_value_var" yes "${profile_values[@]}"
done
if [ "${EFFORT_PROFILE:-static}" = max ] && [ -z "${RDD_VARIANTS_MAX:-}" ]; then
  echo "edge-coder-run: effort=max requires an explicit RDD_VARIANTS_MAX map; refusing to run baseline variants while labelled max" >&2
  exit 2
fi
if [ -d "$HOME/.git" ]; then
  echo "edge-coder-run: REFUSING — $HOME/.git exists. opencode would snapshot-walk all of \$HOME and hang forever. Remove it first (rm -rf \$HOME/.git)." >&2
  exit 2
fi
if [ ! -d "$DIR/.git" ]; then
  echo "edge-coder-run: $DIR is not a git repo root — refusing to dispatch" >&2
  exit 2
fi

LOCK="$LOCKDIR/edge-coder-$(printf '%s' "$DIR" | md5sum | cut -c1-12).lock"

# ---- the actual dispatch (runs in worker for async, inline for --fg) -----------
run_dispatch() {
  local -a TIMEOUTS
  if [ "$MODE" = fg ]; then TIMEOUTS=("${TIMEOUTS_FG[@]}"); else TIMEOUTS=("${TIMEOUTS_BG[@]}"); fi

  echo "[$(ts)] DISPATCH id=${RUN_ID:-fg} mode=$MODE effort=${EFFORT_PROFILE:-static} dir=$DIR task=${TASK:0:120}" >> "$LOG"
  local HEAD_BEFORE
  HEAD_BEFORE="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo '')"

  # Dispatch protocol: PR-based branch flow (trunk is protected), CI runs the
  # tests on the PR, mandatory independent reviewer, durable EDGE feedback via
  # the collaboration doc, machine-readable trailer.
  local SUFFIX
  read -r -d '' SUFFIX <<'PROTO'


--- DISPATCH PROTOCOL (follow exactly) ---
1. BRANCH DISCIPLINE: {{MAIN}} is branch-protected — direct pushes to {{MAIN}}
   are rejected by GitHub. If HEAD is already on a {{PREFIX}}/* branch for this
   task, continue there; otherwise create {{PREFIX}}/<short-task-slug> from
   {{MAIN}}. Commit there, push with git, and OPEN A PULL REQUEST to {{MAIN}}
   using `gh pr create` — NEVER the github MCP write tools (they auto-reject
   in this non-interactive dispatch and strand the run without a PR).
   A human merges; never merge yourself.
2. Write code and tests. Run targeted local validation when it is feasible and
   safe (the smallest relevant test/lint/type-check); CI remains authoritative
   for the full required suite. If local validation is infeasible, say why.
   TESTS-TO-RUN must state what ran and passed, or what remains for CI.
3. For any non-trivial change, dispatch the reviewer subagent for an
   independent read-only review before finishing. Your own review does not count.
4. If you hit an EDGE boundary (an architecture / method / model / stack
   decision, a question whose answer is external evidence, or a bug that looks
   upstream/platform), do NOT improvise: write a research-request into
   {{DOCS}}/EDGE_COLLABORATION.md under "## Open EDGE requests" using the
   envelope in the shared base brief (ID: CM-YYYYMMDD-NN, Status: open,
   Priority: blocking|high|normal|background) and STOP that thread. If you
   tested an EDGE proposal against real code, add reality-feedback under
   "## Implementation feedback log".
5. ALWAYS end your final message with this exact trailer (the dispatch wrapper
   and EDGE parse it):
=== LOOP STATUS ===
BRANCH: <current git branch>
COMMITS: <new short shas this dispatch created, or none>
PR: <pull request URL, or none>
REVIEWER: <Pass | Pass with risks | Fail | not-run> — <one line why>
EDGE-REQUEST: <none | CM-YYYYMMDD-NN priority=blocking|high|normal — one line what you need>
TESTS-TO-RUN: <only what CI cannot run, or none>
=== END ===
PROTO
  SUFFIX="${SUFFIX//\{\{MAIN\}\}/$MAIN_BRANCH}"
  SUFFIX="${SUFFIX//\{\{PREFIX\}\}/$BRANCH_PREFIX}"
  SUFFIX="${SUFFIX//\{\{DOCS\}\}/$DOCS_DIR}"

  # Classify why a tier failed so the ledger + chat messages say "rate-limited"
  # instead of a bare rc. opencode has NO native retry/fallback — this wrapper's
  # tier ladder is the fallback layer, so the reason matters.
  classify_failure() { # classify_failure <rc> <stderr-file>
    local rc="$1" ef="$2"
    if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then echo "hard-timeout"; return; fi
    if grep -qiE 'rate.?limit|too many requests|429' "$ef" 2>/dev/null; then echo "rate-limited"; return; fi
    if grep -qiE 'quota|insufficient|credit|billing|payment required|402' "$ef" 2>/dev/null; then echo "quota/billing"; return; fi
    if grep -qiE 'unauthorized|invalid api key|401|403|forbidden' "$ef" 2>/dev/null; then echo "auth"; return; fi
    if grep -qiE 'overloaded|capacity|503|529' "$ef" 2>/dev/null; then echo "provider-overloaded"; return; fi
    if grep -qiE 'opencode error' "$ef" 2>/dev/null; then echo "provider-error"; return; fi
    echo "empty-or-error-output"
  }

  local i=0 M TO V RC OUT PARTIAL USED_MODEL="" USED_VARIANT="" ERRTMP REASON FAIL_SUMMARY=""
  for M in "${MODELS[@]}"; do
    TO="${TIMEOUTS[$i]:-1500}"
    V="${VARIANTS[$i]:-default}"
    i=$((i+1))
    local -a VARIANT_ARGS=()
    if [ -n "$V" ] && [ "$V" != "default" ] && [ "$V" != "-" ]; then
      VARIANT_ARGS=(--variant "$V")
    fi

    # Partial-work handoff: if an earlier tier moved HEAD or left a dirty tree,
    # tell this tier to continue rather than restart.
    PARTIAL=""
    local HEAD_NOW DIRTY
    HEAD_NOW="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo '')"
    DIRTY="$(git -C "$DIR" status --porcelain 2>/dev/null | head -1)"
    if [ $i -gt 1 ] && { [ "$HEAD_NOW" != "$HEAD_BEFORE" ] || [ -n "$DIRTY" ]; }; then
      PARTIAL="IMPORTANT — PARTIAL WORK EXISTS from a previous attempt that timed out:
the working tree and/or new commits already contain progress on this exact task.
FIRST run git log --oneline -5 and git status, read what exists, and CONTINUE
from it. Do NOT restart from scratch and do NOT revert existing progress.

"
      echo "[$(ts)] PARTIAL-WORK handoff to tier $M variant=${V:-default} (HEAD moved or dirty tree)" >> "$LOG"
    fi

    echo "[$(ts)] TRY model=$M variant=${V:-default} timeout=${TO}s" >> "$LOG"
    # --- Liveness probe first: short prompt, short timeout ---
    echo "[$(ts)] PROBE model=$M" >> "$LOG"
    PROBE_OUT="$( { cd "$DIR" && \
      timeout --signal=TERM --kill-after=10 "$TO" \
      "$OPENCODE" run --format json --model "$M" "${VARIANT_ARGS[@]}" --agent "$AGENT" "say hello"; } 2>/dev/null | \
      python3 -c '
import sys, json
texts = []
has_text = False
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("type") == "text":
        has_text = True
        t = e.get("text") or e.get("part", {}).get("text")
        if t:
            texts.append(t)
if not has_text:
    sys.exit(1)
print("".join(texts))
')"
    PROBE_RC=$?
    if [ $PROBE_RC -ne 0 ]; then
      echo "[$(ts)] PROBE-FAIL model=$M rc=$PROBE_RC -> next tier" >> "$LOG"
      FAIL_SUMMARY="${FAIL_SUMMARY}${M##*/}: probe-fail → "
      continue
    fi
    echo "[$(ts)] PROBE-OK model=$M — dispatching real task" >> "$LOG"
    # --- Real task: model is alive, give it work time ---
    WORK_TO=3600
    # Model override per tier — the wrapper's RDD_MODELS chain IS the fallback.
    # Reviewer subagent inherits the model from opencode config.
    # OCRC captures opencode/timeout's own exit code — the pipeline otherwise
    # reports the JSON parser's status, which masks timeout's 124 and turns
    # every hard-timeout into "empty-or-error-output" in the ledger.
    ERRTMP="$(mktemp /tmp/edge-coder-stderr.XXXXXX)"
    OCRC="$(mktemp /tmp/edge-coder-rc.XXXXXX)"
    STREAM_LOG="$RUNS_DIR/stream.log"
    # Rotate if over 10MB
    if [ -f "$STREAM_LOG" ] && [ "$(stat -c%s "$STREAM_LOG" 2>/dev/null || echo 0)" -gt 10485760 ]; then
      mv "$STREAM_LOG" "$STREAM_LOG.old" 2>/dev/null || true
    fi
    OUT="$( { cd "$DIR" && \
      timeout --signal=TERM --kill-after=30 "$WORK_TO" \
      "$OPENCODE" run --format json --model "$M" "${VARIANT_ARGS[@]}" --agent "$AGENT" "${PARTIAL}${TASK}${SUFFIX}"; echo $? >"$OCRC"; } 2>>"$ERRTMP" | \
      tee "$STREAM_LOG" | \
      python3 -c '
import sys, json
texts = []
has_error = False
has_text = False
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("type") == "error":
        has_error = True
        err = e.get("error", "")
        if err:
            print(f"opencode error: {err}", file=sys.stderr)
    elif e.get("type") == "text":
        has_text = True
        t = e.get("text") or e.get("part", {}).get("text")
        if t:
            texts.append(t)
if has_error or not has_text:
    sys.exit(1)
print("".join(texts))
')"
    RC=$?
    OPENCODE_RC="$(cat "$OCRC" 2>/dev/null || echo '')"
    rm -f "$OCRC"
    # Prefer opencode's own nonzero exit (124/137 = timeout kill) over the
    # parser's generic 1 when classifying the failure.
    [ -n "$OPENCODE_RC" ] && [ "$OPENCODE_RC" != 0 ] && [ $RC -ne 0 ] && RC="$OPENCODE_RC"
    cat "$ERRTMP" >> "$LOG" 2>/dev/null
    if [ $RC -ne 0 ]; then
      REASON="$(classify_failure "$RC" "$ERRTMP")"
      rm -f "$ERRTMP"
      echo "[$(ts)] FAIL model=$M rc=$RC reason=$REASON -> next tier" >> "$LOG"
      FAIL_SUMMARY="${FAIL_SUMMARY}${M##*/}: ${REASON} → "
      continue
    fi
    rm -f "$ERRTMP"
    echo "[$(ts)] OK model=$M variant=${V:-default}" >> "$LOG"
    USED_MODEL="$M"
    USED_VARIANT="$V"
    break
  done

  if [ -z "$USED_MODEL" ]; then
    echo "[$(ts)] ALL MODELS FAILED id=${RUN_ID:-fg}" >> "$LOG"
    echo "edge-coder-run: all ${#MODELS[@]} model tiers failed (see $LOG)" >&2
    if [ "$MODE" = bg ]; then
      send_tg "❌ coder dispatch ${RUN_ID} FAILED — all ${#MODELS[@]} model tiers down: ${FAIL_SUMMARY% → } ✗
Task: ${TASK:0:160}…
Log: $RUNS_DIR/${RUN_ID}.log"
    fi

    return 1
  fi

  # ---- success path ---------------------------------------------------------
  printf "opencode using configured model\n\n"
  printf '%s\n' "$OUT"

  # Trailer verification (mechanical — do not trust model adherence).
  local TRAILER_OK="yes" REVIEWER_VERDICT="missing" REVIEWER_DETAIL=""
  if ! printf '%s' "$OUT" | grep -q '=== LOOP STATUS ==='; then
    TRAILER_OK="MISSING"
    echo "[$(ts)] WARN trailer missing (model=$USED_MODEL)" >> "$LOG"
  else
    REVIEWER_LINE="$(printf '%s\n' "$OUT" | awk '/^=== LOOP STATUS ===/{in_loop=1; next} /^=== END ===/{in_loop=0} in_loop && /^REVIEWER:/{line=$0} END{print line}')"
    REVIEWER_DETAIL="${REVIEWER_LINE#REVIEWER: }"
    case "${REVIEWER_DETAIL%% — *}" in
      Pass) REVIEWER_VERDICT=pass ;;
      "Pass with risks") REVIEWER_VERDICT=pass-with-risks ;;
      Fail) REVIEWER_VERDICT=fail ;;
      not-run) REVIEWER_VERDICT=not-run ;;
      *) REVIEWER_VERDICT=missing ;;
    esac
  fi
  local TASK_CLASS=nontrivial

  # Loop closer: branch, commits, PR, open EDGE requests, nudge.
  local branch head_after commits collab open_reqs pr_url pr_num
  branch="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  head_after="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo '')"
  if [ -n "$HEAD_BEFORE" ] && [ -n "$head_after" ] && [ "$HEAD_BEFORE" != "$head_after" ]; then
    commits="$(git -C "$DIR" log --oneline "${HEAD_BEFORE}..${head_after}" 2>/dev/null | head -10)"
    changed_files="$(git -C "$DIR" diff --name-only "${HEAD_BEFORE}..${head_after}" 2>/dev/null)"
    if [[ "${TASK,,}" =~ ^[[:space:]]*(docs?|typo|spelling|copy|comment|formatting)(:|[[:space:]]) ]] \
       && [ -n "$changed_files" ] \
       && ! printf '%s\n' "$changed_files" | grep -qEv '(^|/)(docs?|notes?)/|\.(md|txt|rst)$'; then
      TASK_CLASS=trivial
    fi
  else
    commits="(no new commits — coder may have left work uncommitted or committed on another branch)"
  fi
  pr_url=""; pr_num=""
  if [ "$HAVE_GH" = 1 ] && [ "$branch" != "$MAIN_BRANCH" ] && [ "$branch" != "?" ]; then
    read -r pr_num pr_url < <(cd "$DIR" && timeout 25 gh pr list --head "$branch" --state open \
      --json number,url -q '.[0] // empty | "\(.number) \(.url)"' 2>/dev/null) || true
    [ "$pr_num" = "null" ] && { pr_num=""; pr_url=""; }
  fi
  echo ""
  echo "=== LOOP CLOSER (wrapper) ==="
  echo "effort profile: ${EFFORT_PROFILE:-static}"
  echo "model: $USED_MODEL"
  echo "variant: ${USED_VARIANT:-default}"
  [ -n "$FAIL_SUMMARY" ] && echo "fallback path: ${FAIL_SUMMARY}${USED_MODEL##*/}"
  echo "branch: $branch"
  echo "trailer: $TRAILER_OK"
  echo "reviewer verdict: $REVIEWER_VERDICT${REVIEWER_DETAIL:+ — $REVIEWER_DETAIL}"
  echo "review trust limit: model-reported trailer parsed mechanically; the wrapper cannot prove an independent reviewer actually ran"
  echo "gate readiness: $([ "$TASK_CLASS" = trivial ] || { [ "$TRAILER_OK" = yes ] && [[ "$REVIEWER_VERDICT" = pass* ]]; } && echo eligible-for-CI-gate || echo BLOCKED-by-review)"
  echo "PR: ${pr_url:-none found for head branch}"
  echo "new commits:"
  printf '%s\n' "$commits"

  # Persist the reviewer gate on GitHub so a later/on-another-machine gate
  # sweep can enforce it. This attests only what the model reported; it is not
  # cryptographic proof that the reviewer ran.
  if [ "$HAVE_GH" = 1 ] && [ -n "$pr_num" ]; then
    review_sha="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || true)"
    review_ready=no
    if [ "$TASK_CLASS" = trivial ] || { [ "$TRAILER_OK" = yes ] && [[ "$REVIEWER_VERDICT" = pass* ]]; }; then review_ready=yes; fi
    marker="<!-- edge-review-gate sha=$review_sha class=$TASK_CLASS verdict=$REVIEWER_VERDICT ready=$review_ready trust=model-reported -->"
    (cd "$DIR" && timeout 25 gh pr comment "$pr_num" --body "$marker") >>"$LOG" 2>&1 || \
      echo "[$(ts)] WARN could not persist reviewer marker for PR#$pr_num" >> "$LOG"
  fi

  open_reqs=""
  collab="$DIR/$DOCS_DIR/EDGE_COLLABORATION.md"
  if [ -f "$collab" ]; then
    open_reqs="$(awk '
      function flush() {
        if (active && title!="" && stat ~ /open/ && prio ~ /blocking|high/)
          print "  " title "  [" id "  " prio "]"
      }
      /^## / { if ($0 !~ /^## Open EDGE requests/) { flush(); active=0; title="" } }
      /^## Open EDGE requests/ { active=1 }
      /^### / { flush(); title=$0; id=""; stat=""; prio="" }
      /^ID:/       { id=$0 }
      /^Status:/   { stat=$0 }
      /^Priority:/ { prio=$0 }
      END { flush() }
    ' "$collab" 2>/dev/null)"
    if [ -n "$open_reqs" ]; then
      echo "OPEN blocking/high EDGE requests (coder handed research back):"
      printf '%s\n' "$open_reqs"
    else
      echo "no open blocking/high EDGE requests filed"
    fi
  fi
  echo "=== END LOOP CLOSER ==="
  echo "MODEL_USED=$USED_MODEL" >&2
  echo "VARIANT_USED=${USED_VARIANT:-default}" >&2

  # Async completion push to the project thread (fg already shows all of this inline).
  if [ "$MODE" = bg ]; then
    msg="✅ coder dispatch ${RUN_ID} done (opencode-configured model)
effort profile: ${EFFORT_PROFILE:-static}
variant: ${USED_VARIANT:-default}"
    [ -n "$FAIL_SUMMARY" ] && msg="$msg
fallback path: ${FAIL_SUMMARY}${USED_MODEL##*/}"
    msg="$msg
branch: $branch
PR: ${pr_url:-none}
trailer: $TRAILER_OK
reviewer: $REVIEWER_VERDICT (model-reported; wrapper cannot prove reviewer execution)
gate readiness: $([ "$TASK_CLASS" = trivial ] || { [ "$TRAILER_OK" = yes ] && [[ "$REVIEWER_VERDICT" = pass* ]]; } && echo eligible-for-CI-gate || echo BLOCKED-by-review)
commits:
${commits}"
    [ -n "$open_reqs" ] && msg="$msg
⚠️ OPEN EDGE request(s) filed — research handoff waiting in $DOCS_DIR/EDGE_COLLABORATION.md:
$open_reqs"
    msg="$msg
full output: $RUNS_DIR/${RUN_ID}.log"
    send_tg "$msg" && echo "[$(ts)] COMPLETION message sent id=${RUN_ID}" >> "$LOG"
  elif [ -n "$open_reqs" ]; then
    # fg nudges only when a handoff needs attention.
    send_tg "coder: open blocking/high EDGE request(s) after a $branch dispatch — research handoff waiting in $DOCS_DIR/EDGE_COLLABORATION.md."
  fi

  # CI watcher: detached, closes the lock fd so the next dispatch isn't blocked
  # while checks run. Posts the verdict (pass/fail/still-pending) to the thread.
  if [ "$HAVE_GH" = 1 ] && [ -n "$pr_num" ]; then
    (
      exec 9>&- 2>/dev/null || true
      n=0
      while [ $n -lt $CI_POLL_MAX ]; do
        sleep $CI_POLL_SECS
        n=$((n+1))
        checks="$(cd "$DIR" && timeout 25 gh pr checks "$pr_num" --json name,bucket 2>/dev/null)" || continue
        [ -n "$checks" ] || continue
        pending="$(printf '%s' "$checks" | jq '[.[]|select(.bucket=="pending")]|length' 2>/dev/null || echo 1)"
        if [ "$pending" = "0" ]; then
          fails="$(printf '%s' "$checks" | jq -r '[.[]|select(.bucket=="fail")|.name]|join(", ")' 2>/dev/null)"
          if [ -n "$fails" ]; then
            send_tg "❌ PR #$pr_num CI: FAILED — $fails
$pr_url"
          elif [ "$TASK_CLASS" = nontrivial ] && { [ "$TRAILER_OK" != yes ] || [[ "$REVIEWER_VERDICT" != pass* ]]; }; then
            send_tg "⛔ PR #$pr_num CI is green, but reviewer verdict is $REVIEWER_VERDICT — NOT gate-ready. This verdict is parsed from model output and cannot prove reviewer execution.
$pr_url"
          else
            send_tg "✅ PR #$pr_num CI: all checks green; reviewer gate eligible — ready for human merge. Reviewer evidence is model-reported, not independently provable by the wrapper.
$pr_url"
            # Trigger an immediate gate sweep so the merge button appears now,
            # without waiting for the next on-demand /gate sweep.
            if [ -x "$GATE_SCRIPT" ]; then
              bash "$GATE_SCRIPT" sweep >>"$LOG" 2>&1 &
              echo "[$(ts)] gate sweep triggered for PR#$pr_num" >> "$LOG"
            fi
          fi
          echo "[$(ts)] CI verdict sent PR#$pr_num fails='$fails'" >> "$LOG"
          exit 0
        fi
      done
      send_tg "⏳ PR #$pr_num CI: still pending after $((CI_POLL_SECS*CI_POLL_MAX/60)) min — check manually: $pr_url"
    ) </dev/null >>"$LOG" 2>&1 &
    disown 2>/dev/null || true
  fi

  return 0
}

# ---- entry ----------------------------------------------------------------------
if [ "$WORKER" = 1 ]; then
  # Worker: inherits the flock fd 9 from the parent; lock releases when we exit
  # (the CI watcher closes its copy explicitly).
  echo "pid=$$ started=$(ts) mode=worker effort=${EFFORT_PROFILE:-static} task=${TASK:0:80}" > "$LOCK.holder"
  run_dispatch
  rc=$?
  rm -f "$LOCK.holder" 2>/dev/null
  exit $rc
fi

# Parent: take the lock (fd 9), then either run inline (--fg) or detach a worker
# that inherits fd 9 — so there is no unlocked gap between parent and worker.
exec 9>"$LOCK"
if ! flock -n 9; then
  holder="$(cat "$LOCK.holder" 2>/dev/null || echo 'unknown holder')"
  echo "[$(ts)] LOCKED — concurrent dispatch refused for $DIR ($holder)" >> "$LOG"
  echo "edge-coder-run: a dispatch is already running for $DIR — $holder. Refusing a second concurrent dispatch; wait for its completion message or check: edge-coder-run.sh status" >&2
  exit 3
fi

if [ "$MODE" = fg ]; then
  echo "pid=$$ started=$(ts) mode=fg effort=${EFFORT_PROFILE:-static} task=${TASK:0:80}" > "$LOCK.holder"
  run_dispatch
  rc=$?
  rm -f "$LOCK.holder" 2>/dev/null
  exit $rc
fi

RUN_ID="run-$(date +%Y%m%d-%H%M%S)-$RANDOM"
echo "pid=parent started=$(ts) mode=bg id=$RUN_ID effort=${EFFORT_PROFILE:-static} task=${TASK:0:80}" > "$LOCK.holder"
setsid bash "$0" --worker "$RUN_ID" --dir "$DIR" "$TASK" \
  >>"$RUNS_DIR/$RUN_ID.log" 2>&1 </dev/null &
disown 2>/dev/null || true
echo "[$(ts)] DETACHED id=$RUN_ID pid=$! dir=$DIR" >> "$LOG"
echo "DISPATCHED $RUN_ID — coder is running in the background."
echo "Completion summary (model, branch, commits, PR) and the CI verdict will be posted to the project thread automatically."
echo "Full output will land in: $RUNS_DIR/$RUN_ID.log"
echo "Check progress: edge-coder-run.sh status"
exit 0
