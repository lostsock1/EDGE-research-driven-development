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

## Reading the completion message

```
✅ coder dispatch run-20260703-064023-14383 done on `openai/gpt-5.5`
fallback path: gpt-5.5: rate-limited → deepseek-v4-pro      <- only when tiers failed
branch: cm/qdq-retrieval-parity
PR: https://github.com/you/repo/pull/12
trailer: yes
commits:
a1b2c3d Add retrieval parity eval script
full output: ~/.local/state/edge-rdd/runs/run-...log
```

- **model line** — which tier actually did the work; a fallback is never silent.
- **PR: none + no commits** — the run was likely beheaded (see troubleshooting) or the coder stopped at a research boundary; check the run log and `EDGE_COLLABORATION.md`.
- **trailer: MISSING** — the model skipped the mandatory status trailer; the wrapper's own git/PR facts above are still reliable, but treat the model's prose claims with suspicion.
- **⚠️ OPEN EDGE request(s)** — the coder handed research back; that's the loop working, not a failure. EDGE answers, promotes, re-dispatches.

Then, minutes later: `✅ PR #12 CI: all checks green — ready for human merge.` — that's your cue. Merging is always yours.

## Failure classifications (ledger + failure messages)

| Label | Meaning | Usual action |
|---|---|---|
| `rate-limited` | provider 429 | none — next tier already took over |
| `quota/billing` | credits exhausted / 402 | top up that provider |
| `auth` | key invalid/revoked | rotate the key in opencode config |
| `provider-overloaded` | 503/529 capacity | none — retry later or rely on tiers |
| `hard-timeout` | tier hit its RDD_TIMEOUTS_* ceiling | task too big? split the work order |
| `provider-error` | opencode error event | read the run log |
| `empty-or-error-output` | model returned nothing usable | read the run log; often a model-side stall |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Dispatch refused: `a dispatch is already running` (exit 3) | per-repo lock held | wait for its completion message, or `edge-coder-run.sh status` to see the holder; a crashed worker releases the lock on process exit |
| Completion shows `trailer: MISSING`, `PR: none`, no commits | run beheaded mid-task — most often an `ask` permission auto-rejecting in non-interactive mode | grep the run log for `auto-rejecting`; flip that permission to `allow` (safety lives in branch protection) or to `deny` if it truly must not happen |
| Wrapper refuses: `$HOME/.git exists` | stray git repo at home dir | `rm -rf $HOME/.git` (verify it's stray first!) |
| All tiers `rate-limited`/`quota` | provider account issue | fix billing/keys; the failure message names each tier's reason |
| Coder "succeeded" but pushed nothing | it committed on the wrong branch or left work uncommitted | the completion message says exactly that; re-dispatch — the partial-work handoff tells the next run to continue, not restart |
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

The wrapper's config file describes the **default** project. A second project reuses the same wrapper and coder agents with per-dispatch overrides — no second install needed:

```bash
EDGE_CODER_THREAD=<other-topic-id> \
bash ~/.openclaw/shared-scripts/edge-coder-run.sh --dir <other-repo-root> '<task>'
```

(`EDGE_CODER_TARGET` too if the thread lives in a different group.) Bake exactly this command into the second project's charter so its research agent never dispatches with the defaults. Each project gets its own charter + RESUME.md (`workspace-edge/` templates rendered with that project's values), its own topic binding, and its own `docs/agent/` seed in its repo. Note: the per-repo lock is already per-`--dir`, so two projects can dispatch concurrently; the completion messages route to each project's own thread via the env override.

Caveat: plain `RDD_*` environment variables do **not** override the config — sourcing the config file clobbers them. If the second project needs different values for anything beyond target/thread (`RDD_MAIN_BRANCH`, `RDD_DOCS_DIR`, models…), give it its own config file and point the dispatch at it:

```bash
EDGE_RDD_CONFIG=~/.config/edge-rdd/<project>.env \
bash ~/.openclaw/shared-scripts/edge-coder-run.sh --dir <other-repo-root> '<task>'
```

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
| `/gate` or `/gate sweep` (or `gate sweep`) | run the sweep now (heartbeat does it every 6h anyway) |
| `/gate pending` (or `gate pending`) | list open asks with their `eg:<id>` handles |
| `/gate status` | pending + the last few executed/failed actions |
| `/gate act <id>` | execute an already-approved action (same as tapping its button) |

State + audit log: `~/.local/state/edge-rdd/pr-gate/` (`state.json`, `gate.log`).
Knobs (merge strategy, re-ask window, button cap): `RDD_GATE_*` in `template.env.example`.
Red / pending-CI PRs are never offered as gate actions — they ride `fix the red PR`.

## Weekly hygiene (or just tell the agent: `sweep`)

open PRs · `cm/*` branches with no PR · failed scheduled workflow runs · `TASKS.md` boxes vs reality · `PROJECT_STATE.md` truthfulness · wrapper ledger for repeated tier failures (a persistently failing tier deserves demotion in `RDD_MODELS`).
