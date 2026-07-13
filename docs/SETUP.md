# Setup

End-to-end install on a fresh OpenClaw server. Time: ~30–45 min, most of it GitHub/CI.

## 0. Prerequisites

- **OpenClaw** gateway running as a user systemd service, with a Telegram channel connected and a group with forum topics enabled.
- **opencode** installed (`~/.opencode/bin/opencode`) with API keys for at least two coder models (the tier ladder needs a fallback).
- **gh** CLI authed as the GitHub account that owns the project repo (`gh auth status`), with `repo` and `workflow` scopes (`gh auth refresh -s workflow` if pushes of workflow files are rejected).
- On PATH (for the wrapper): `flock`, `setsid`, `timeout`, `git`, `jq`, `python3`. Set `RDD_PATH_PREPEND` if the gateway spawns processes with a minimal PATH.
- A project repository on GitHub with a local clone on this server.
- **No git repo at `$HOME`** — `ls -d ~/.git` must fail. If it exists, opencode will hang on every dispatch.

## 1. Configure

```bash
git clone https://github.com/lostsock1/EDGE-evidence-driven-git-engineering
cd EDGE-evidence-driven-git-engineering
cp template.env.example template.env
$EDITOR template.env        # fill in EVERY value — see comments in the file
```

The important ones: `RDD_REPO_SLUG`/`RDD_REPO_DIR`, `RDD_MAIN_BRANCH`, `RDD_TG_TARGET`/`RDD_TG_THREAD`, `RDD_OPERATOR_TG_USER_ID`, and the model knobs (`RDD_MODELS`, `RDD_CODER_MODEL`, `RDD_EDGE_MODEL_PRIMARY`) — the template ships **no** model choices; every `provider/model` placeholder must become one of yours.

## 2. Render and inspect

```bash
./install.sh          # renders into ./rendered/ — nothing is touched yet
```

Read through `rendered/` once. This is your chance to adapt the coder's permission map (`rendered/opencode/agents/code-monkeys/coder.md`) and the per-area checks table to your stack before anything goes live.

## 3. Apply

```bash
./install.sh --apply
```

This installs (with timestamped backups under `~/.config/edge-rdd/backups/`):

| What | Where |
|---|---|
| shared model/timeout/variant policy | `~/.config/edge-rdd/config.env` |
| project identity (repo/chat/branch/checks) | `~/.config/edge-rdd/<slug>.env` |
| PR-gate hub + research dispatch configs | `~/.config/edge-rdd/gate.env`, `~/.config/edge-rdd/research.env` |
| dispatch wrapper + PR gate + research scripts | `~/.openclaw/shared-scripts/` (symlinks into the workspace) |
| `/gate` + `/research` skills | `~/.openclaw/skills/{gate,research}` (symlinks) |
| opencode agents | `~/.config/opencode/agents/code-monkeys/` |
| communication contract | `~/.openclaw/workspace-<agent>/USER.md` |
| persona library + SOUL.md | `~/.openclaw/workspace-<agent>/personas/` (default `RDD_PERSONA=FRONTIER` seeded to `SOUL.md`; existing SOUL.md never overwritten) |
| workspace guide | `~/.openclaw/workspace-<agent>/AGENTS.md` (seeded once, never overwritten) |
| identity card | `~/.openclaw/workspace-<agent>/IDENTITY.md` (seeded once) |
| skill registry | `~/.openclaw/workspace-<agent>/SKILL-REGISTRY.md` (seeded once) |
| persona marker | `~/.openclaw/workspace-<agent>/PERSONA.md` (regenerated from SOUL.md on every apply) |
| project charter | `~/.openclaw/workspace-<agent>/projects/<slug>/PROJECT.md` |
| note templates | `~/.openclaw/workspace-<agent>/templates/` (6 templates, refreshed on every apply) |
| repo handoff docs | `<repo>/docs/agent/` (only files that don't exist yet) |

## 4. OpenClaw config (manual, reviewed)

1. Back up first: `cp ~/.openclaw/openclaw.json ~/.openclaw/backups/openclaw.json.$(date +%Y%m%d_%H%M%S)`
2. Merge `rendered/openclaw/agent.edge.json5` into `agents.list[]`.
   **Heartbeat caveat:** the snippet includes a `heartbeat` block. In OpenClaw,
   the moment ANY agent defines a `heartbeat` block, agents WITHOUT one stop
   running heartbeats — if other agents on this gateway rely on default
   heartbeats, give each of them an explicit `heartbeat: { every: "30m" }`
   (that preserves the default exactly). The heartbeat runs only the portable Superior Architecture integrity check;
   the PR gate remains on-demand via `/gate sweep`.
3. Merge `rendered/openclaw/topic.project-thread.json5` into your Telegram group's `topics` map, and `rendered/openclaw/topic.hub-thread.json5` for the coordination/gate-hub thread.
4. **Enable inline-button callbacks (required for the gate's tap-to-approve).**
   Telegram's `capabilities.inlineButtons` defaults to `allowlist`, which
   silently drops the gate's approval-button taps — the button renders but a tap
   produces *no inbound event at all*. Set it explicitly on the telegram channel:

   ```json5
   channels: {
     telegram: {
       capabilities: { inlineButtons: "all" },  // or "group" if the gate thread is a group
       // ...
     },
   }
   ```

   Without this, approvals only work via a `👍`/`approve` reply, not the buttons.

   > **Why the gate uses command-style buttons.** OpenClaw encodes a *callback*
   > button's value into an opaque payload, and its Telegram handler silently
   > drops opaque callbacks that no plugin claims — so a tap does nothing. The
   > gate therefore emits **`command` buttons** (`action.type: "command"`,
   > `command: "/gate act eg:<id>"`), which Telegram delivers to the agent as the
   > native command text `/gate act eg:<id>`; the `gate` skill runs it. This is
   > already how `edge-pr-gate.sh` builds its buttons — no action needed, just
   > don't switch them back to `callback` actions.
5. Validate and restart:

```bash
openclaw config validate
systemctl --user restart openclaw-gateway
openclaw channels status     # wait for Telegram to reconnect (~15-40s)
```

## 5. GitHub: CI + branch protection

1. Copy `project-repo/.github/workflows/ci.yml.example` into your repo as `.github/workflows/ci.yml`, adapt the jobs to your stack, commit, push, and **watch it run green once** (protection needs existing check contexts).
2. Commit the seeded `docs/agent/` handoff docs (fill in the `<!-- ADAPT -->` sections of `PROJECT_STATE.md`, `TASKS.md`, `QUALITY_GATES.md` — especially your project invariants).
3. Apply protection:

```bash
EDGE_RDD_CONFIG=~/.config/edge-rdd/<slug>.env bash github/protect-branch.sh
```

4. Verify the gate actually bites:

```bash
cd $RDD_REPO_DIR && git push origin HEAD:$RDD_MAIN_BRANCH   # must be REJECTED
```

## 6. Smoke test

```bash
# wrapper alive, lock free, ledger empty
bash ~/.openclaw/shared-scripts/edge-coder-run.sh status

# full dry run: real dispatch pipeline, chat messages printed instead of sent
EDGE_CODER_DRYRUN_MSG=1 bash ~/.openclaw/shared-scripts/edge-coder-run.sh --fg \
  'ro Read docs/agent/PROJECT_STATE.md and summarize the current project state. Do not write anything.'
```

Expected: a probe line in the ledger, a summary, and a `=== LOOP CLOSER ===` block with `trailer: yes` plus the effort profile, variant, and model.

Then from Telegram, in the project topic, ask the research agent to run the same `status` command — this proves the agent → wrapper elevated-exec path.

PR gate dry run (no messages sent, nothing executed):

```bash
bash ~/.openclaw/shared-scripts/edge-pr-gate.sh sweep --dry-run
```

Expected: one block per configured project listing PRs/branches and only actions
whose checks are all green, whose named required contexts are present/pass, and
whose current-head reviewer marker is eligible. A no-CI PR is never offered. The actions it
*would* offer as buttons, and `ALL_CLEAN` at the end if the repos are trunk-only.
The real sweep runs on-demand via `/gate sweep` in chat; approvals are
described in [OPERATIONS.md](OPERATIONS.md#the-pr-gate-approve-merges-from-your-phone).

## 6b. Optional: the OpenScience research companion

The dual-research protocol needs the sandboxed research workbench. Follow
[openscience/README.md](../openscience/README.md) (binary + workspace, your
model choices in `openscience.json`, keys in `openscience.env`, the hardened
systemd unit), then verify:

```bash
bash ~/.openclaw/shared-scripts/openscience-smoke.sh --health-only   # no model use
bash ~/.openclaw/shared-scripts/openscience-smoke.sh                 # one real dispatch
```

## 7. Kick off the thread

```bash
bash scripts/kickoff.sh            # add --dry-run to preview without sending
```

This **preflights the GitHub connection** — authenticated `gh`, reachable repo, local clone whose origin matches, protected trunk (warns if not), seeded handoff docs — then posts two messages into the project thread, rendered with your values:

- the **development kickoff**: tells the agent to read its charter + repo state and propose the first work order, then wait for your go;
- the **command palette** — *pin this one* (long-press → Pin). It's the day-to-day driving surface: `status`, `go`, `next`, `work order for <thing>`, `research`, `promote`, `sweep`, `merged`, `what happened`, …

The GitHub repo is an expected precondition by design: kicking off a thread whose repo isn't wired strands the agent at its first dispatch. For a second project on the same server, run it with that project's config: `EDGE_RDD_CONFIG=~/.config/edge-rdd/<project>.env bash scripts/kickoff.sh`.

## 8. First real cycle

The kickoff already asked the agent to propose the first work order. Reply **go**, watch the `DISPATCHED <run-id>` reply, the ✅ completion message, the CI verdict — and merge the PR on GitHub. That's the loop.

## Updating later

Re-run `./install.sh --apply` after editing `template.env` or pulling template updates — backups are automatic, and live-edited repo docs are never overwritten (diff `rendered/` manually when you want upstream doc changes).
