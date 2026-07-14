# Operations

Day-to-day driving, message anatomy, and troubleshooting.

## Short commands that keep the loop running

Send these to the research agent in the project thread:

| You say | It does |
|---|---|
| `status` | resume from disk (RESUME.md + repo state), report plainly |
| `research <topic/link>` | research, distill to mechanisms, stage what matters |
| `propose` | turn the best staged finding into a work order and post it for your go |
| `go` | dispatch the posted work order to the coders |
| `sweep` | GitHub hygiene pass: open PRs, stale branches, failed runs, doc drift |
| `answer requests` | work the open items in EDGE_COLLABORATION.md |

The agent must always reply in the contract shape: plain-lingo summary → your options with tradeoffs → one recommendation with the why.

## The gapped lab — running contained experiments

EDGE's gapped lab runs experiments in ephemeral Docker containers. Every run requires a pre-registered protocol (`protocol.yaml`) with hypothesis, rival, and refutation_condition — the lab refuses to run without them.

### Quick start

```bash
# Build the lab image (once, or after Dockerfile changes)
lab/lab-run.sh --image

# Create a new experiment from template
lab/lab-run.sh --new my-hypothesis

# Fill in lab/experiments/my-hypothesis/protocol.yaml and run.sh
# Then run it:
lab/lab-run.sh lab/experiments/my-hypothesis

# List past experiments and their outcomes
lab/lab-run.sh --list

# Clean up old experiment artifacts
lab/lab-run.sh --clean
```

### Container environment

- Python 3.12 + numpy, pandas, scipy, scikit-learn, matplotlib, pytest, duckdb, pyarrow
- System tools: git, curl, jq, yq, sqlite3, graphviz
- Network: `none` by default (air-gapped). Set `LAB_NETWORK=bridge` if needed
- Resources: bounded per run (default 2g memory, 2 CPUs, 600s timeout)
- Mounts: experiment dir at `/lab/experiment/` (rw), workspace projects at `/lab/workspace/projects/` (ro)

### Protocol enforcement

Every experiment dir must contain `protocol.yaml` with at minimum:
- `hypothesis` — the explanation under test
- `rival` — the incompatible alternative
- `refutation_condition` — the result that kills the hypothesis

Create interactively: `lab/protocol.sh --new <slug>`

### Configuration

Override defaults via environment variables:
```bash
LAB_MEMORY=4g LAB_TIMEOUT=1200 LAB_NETWORK=bridge lab/lab-run.sh lab/experiments/my-test
```

See `lab/README.md` for full documentation.

## Reading the completion message

```
✅ coder dispatch run-20260703-064023-14383 done (opencode-configured model)
effort profile: standard
variant: default
fallback path: model-a: rate-limited → model-b      <- only when tiers failed
branch: cm/qdq-retrieval-parity
PR: https://github.com/you/repo/pull/12
trailer: yes
reviewer: pass (model-reported; wrapper cannot prove reviewer execution)
gate readiness: eligible-for-CI-gate
commits:
a1b2c3d Add retrieval parity eval script
full output: ~/.local/state/edge-rdd/runs/run-...log
```

- **effort/variant lines** — which effort profile the dispatch ran at and which opencode variant tier 1 used; the exact model id is in the run log's `=== LOOP CLOSER ===` block.
- **fallback path** — present only when tiers failed over; a fallback is never silent.
- **PR: none + no commits** — the run was likely beheaded (see troubleshooting) or the coder stopped at a research boundary; check the run log and `EDGE_COLLABORATION.md`.
- **trailer/reviewer/gate readiness** — non-trivial work needs a parsed Pass/Pass-with-risks verdict. The verdict is model-reported: the wrapper verifies syntax and head SHA, not that an independent reviewer truly ran.
- **⚠️ OPEN EDGE request(s)** — the coder handed research back; that's the loop working, not a failure. EDGE answers, promotes, re-dispatches.

Then, minutes later, the wrapper reports CI plus reviewer eligibility. The gate independently requires every reported check green, every project-named required context present/pass, and a current-head eligible reviewer marker. No-CI PRs are never chat-mergeable. Merging is always yours.

## Failure classifications (ledger + failure messages)

| Label | Meaning | Usual action |
|---|---|---|
| `probe-fail` | tier failed its liveness probe (dead key, 429, hung provider) | none — next tier already took over |
| `rate-limited` | provider 429 | none — next tier already took over |
| `quota/billing` | credits exhausted / 402 | top up that provider |
| `auth` | key invalid/revoked | rotate the key in opencode config |
| `provider-overloaded` | 503/529 capacity | none — retry later or rely on tiers |
| `hard-timeout` | the real task hit the fixed 3600s work budget (probes use RDD_TIMEOUTS_*) | task too big? split the work order |
| `provider-error` | opencode error event | read the run log |
| `empty-or-error-output` | model returned nothing usable | read the run log; often a model-side stall |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Dispatch refused: `a dispatch is already running` (exit 3) | per-repo lock held | wait for its completion message, or `edge-coder-run.sh status` to see the holder; a crashed worker releases the lock on process exit |
| Completion shows `trailer: MISSING`, `PR: none`, no commits | run beheaded mid-task — most often an `ask` permission auto-rejecting in non-interactive mode | grep the run log for `auto-rejecting`; flip that permission to `allow` (safety lives in branch protection) or to `deny` if it truly must not happen |
| Wrapper refuses: `$HOME/.git exists` | stray git repo at home dir | `rm -rf $HOME/.git` (verify it's stray first!) |
| All tiers `rate-limited`/`quota` | provider account issue | fix billing/keys; the failure message names each tier's reason |
| Coder "succeeded" but pushed nothing | it committed on the wrong branch or left work uncommitted | the completion message distinguishes model-reported state from observed state and explicitly says PR MISSING; commitless/docs-only work may be intentional — inspect the run and partial-work handoff before re-dispatching |
| PR blocked on a check that never runs | required context name ≠ CI job name (renamed job?) | fix the name in ci.yml or re-run `github/protect-branch.sh` with the new contexts |
| CI never triggers | workflow `branches:` filter points at an old/renamed trunk | update `on.push/pull_request.branches` |
| Agent's model failover stopped working | user-pinned session model disables the fallback chain | remove `modelOverride*` from the agent's `sessions.json` with the gateway stopped |
| Chat pushes not arriving | `RDD_TG_TARGET` empty/wrong, or gateway PATH missing the openclaw CLI | check the ledger (`RDD_LOG`) — `send_tg` failures land there |
| Gate approval **button renders but tapping does nothing** (no inbound event in the logs) | Telegram `capabilities.inlineButtons` is at its `allowlist` default, which drops the callback | set `channels.telegram.capabilities.inlineButtons: "all"` (or `"group"`) and restart — see SETUP §4. Meanwhile `👍`/`approve` replies still work |

## Log locations

- **Ledger** (one line per event): `RDD_LOG` — dispatches, tier tries/fails with reasons, CI verdicts, lock refusals.
- **Per-run full output**: `RDD_RUNS_DIR/<run-id>.log` — everything the coder said and the loop closer.
- `edge-coder-run.sh status` — lock state, last 5 runs, ledger tail.

## Rollback

- Wrapper/agents: timestamped backups in `~/.config/edge-rdd/backups/` — copy back and re-run.
- OpenClaw config: your own backup from the setup step; `openclaw config validate` before restart.
- Branch protection off (emergencies only): `gh api -X DELETE repos/OWNER/REPO/branches/BRANCH/protection`

## Multiple projects on one server

`~/.config/edge-rdd/config.env` contains shared model, timeout, and variant policy only. Every project has a `<slug>.env` containing repo/chat/branch/check identity. Select it explicitly (the installer also records one default project):

```bash
EDGE_RDD_CONFIG=~/.config/edge-rdd/<project>.env \
bash ~/.openclaw/shared-scripts/edge-coder-run.sh '<task>'
```

## Effort profiles (how hard the coder thinks)

Every dispatch runs at an effort profile: `fast`, `standard`, `deep`, or `max`.
With `RDD_VARIANT_POLICY=auto` the wrapper classifies the task itself
(security/incident keywords → `max`, debugging/architecture → `deep`, trivial
doc fixes → `fast`, everything else → `standard`) and applies your
`RDD_VARIANTS_<PROFILE>` per-tier variant map. Override per dispatch with a
task prefix — `[effort=deep] fix the flaky retry test` — or the
`EDGE_CODER_EFFORT` env var. The chosen profile is recorded in the ledger, the
lock holder, the loop closer, and the completion message. Variant maps are **yours to define** and must match variants in your opencode
config. Empty fast/standard/deep maps may keep the baseline. `max` requires an
explicit, index-aligned `RDD_VARIANTS_MAX`; the wrapper refuses to run baseline
variants while labelling the dispatch max.

## Research dispatch (/research — the OpenScience companion)

With the optional [OpenScience companion](../openscience/README.md) installed,
every project thread can dispatch sandboxed external research:

| You type | What happens |
|---|---|
| `/research assign "<question>"` | async dispatch; returns `DISPATCHED <ERA-id>`, the finished packet posts back with **Accept / Reject** buttons |
| `/research list` / `/research status` | assignments, packets awaiting approval, workbench health |
| `/research show OSR-<id>` | print a packet |
| `/research accept <handle>` | promote the packet into the knowledge base (`projects/<project>/notes/`) — single-use |
| `/research reject <handle>` | archive without adding to the KB |
| `/research followup <id> "<q>"` | follow-up question referencing a prior packet |

Accepting stores knowledge; it never implements anything. Promotion into a
work order stays the normal staging-ladder step. The dual-research protocol
(every question through BOTH the research agent and OpenScience) is defined in
[research-protocol.md](research-protocol.md).

## Daily dev report (optional cron)

A gateway cron job can post a cross-project daily report to the hub thread.
Create it with the OpenClaw cron API/CLI on the research agent with an
agent-turn payload along these lines:

> Generate the daily development report. Include: (1) what was done in the
> last 24 hours across all projects, (2) current status of each project with
> open PRs and CI state, (3) concrete options for each project, (4) any
> problems or blockers. Run a gate sweep first to get current GitHub state.
> Send it to the hub thread.

## The PR gate: approve merges from your phone

Run `/gate sweep` (or just `gate sweep` in chat) — `edge-pr-gate.sh sweep`
checks every project config in `~/.config/edge-rdd/*.env` on
GitHub — open PRs + CI verdict, and every non-trunk branch. Green
PRs and stale branches become **single-use pending actions**, posted to **one
gate thread** (`RDD_GATE_TG_*` in `~/.config/edge-rdd/gate.env` — set it to your
EDGE coordination thread so every project's asks arrive in one place) as one
message per project, each with an inline button per action, a ⏸ snooze, and a
**plain-language brief per action: what it does, the consequence, and why it's
offered** — so you approve an informed decision, not a bare button. Unchanged
asks are not re-posted for 24h. Goal: **trunk-only repos**.

Approve with one tap (the button), a 👍/✅ reaction, or by replying `approve`.
The agent then runs `act <id>`, which **re-verifies** (PR still open, checks
still green, branch still stale) before executing `gh pr merge --squash
--delete-branch` (or the branch delete), posts the outcome, and burns the id.
A refused/stale action explains itself and does nothing.

When a project has ≥2 pending items the ask also shows a **“☑️ Do all N of the above”** button that approves them all at once — each still re-verified individually before it runs.

The gate is also a slash command (the `gate` skill), so you can drive it directly:

| You type | What happens |
|---|---|
| `/gate` or `/gate sweep` (or `gate sweep`) | run the sweep now (the dispatch wrapper also auto-sweeps when a PR's CI goes green) |
| `/gate pending` (or `gate pending`) | list open asks with their `eg:<id>` handles |
| `/gate status` | pending + the last few executed/failed actions |
| `/gate act <id>` | execute an already-approved action (same as tapping its button) |

State + audit log: `~/.local/state/edge-rdd/pr-gate/` (`state.json`, `gate.log`).
Knobs (merge strategy, re-ask window, button cap): `RDD_GATE_*` in `template.env.example`.
Red / pending-CI PRs are never offered as gate actions — they ride `fix the red PR`.

## Weekly hygiene (or just tell the agent: `sweep`)

open PRs · `cm/*` branches with no PR · failed scheduled workflow runs · `TASKS.md` boxes vs reality · `PROJECT_STATE.md` truthfulness · wrapper ledger for repeated tier failures (a persistently failing tier deserves demotion in `RDD_MODELS`).
