---
name: dispatch
description: "Coder-run follow-ups — inspect what a dispatch did, re-run it, send a red PR back to be fixed, or one-tap dispatch a staged work order. Usage: /dispatch [list|log <run-id>|diff <run-id>|ci <run-id>|health [run-id]|retry <run-id>|fix <run-id>|go <WO-id>]"
user-invocable: true
---

# Coder Dispatch Follow-up Skill

**You MUST execute the command below and relay its output. Do NOT answer from memory, and do NOT run `opencode` or touch the repo yourself.**

Take the operator's argument after `/dispatch` (everything following the command). If it is empty, use `list`. Then run exactly:

```
bash {{HOME}}/.openclaw/shared-scripts/edge-coder-run.sh <arg>
```

This skill exists because every message the dispatch wrapper posts carries its next steps as inline buttons, and a tapped button arrives as one of these commands. Each one names a run id, which is how the wrapper recovers that run's project, repo, task and PR without the operator having to say which project they mean.

Sub-commands:

**Read-only — these change nothing:**
- (empty) or `list` — recent dispatches, one line each, with project, branch, PR and last known CI verdict.
- `log <run-id>` — the tail of that run's full output. Use when the operator asks what the coder actually did or why something failed.
- `diff <run-id>` — the commits and changed files that run produced.
- `ci <run-id>` — re-read the current CI verdict for that run's PR, right now.
- `health [run-id]` — probe every configured model tier and report which answer. Costs a few seconds per tier and dispatches no work. A ❌ tier is skipped by the fallback ladder, not a dispatch failure.

**These spend a real model run — only on the operator's explicit say-so (a button tap counts):**
- `retry <run-id>` — re-dispatch that run's *original* task, against the same project. Use after an all-tiers-down failure, or when a run produced nothing usable.
- `fix <run-id>` — dispatch "make the failing CI pass" against that run's PR. The coder checks out the existing branch, reads the failing checks, and pushes a fix to that same branch. It does not open a second PR.
- `go <WO-id>` — dispatch a work order the research agent **staged** for you. When it proposes a work order it posts a 🚀 button carrying `/dispatch go <WO-id>`; tapping it recovers the staged task and its project and dispatches — the one-tap replacement for typing "go". Single-use, so a double-tap can't double-dispatch (a second `go` reports the work order is already dispatched).

Rules:
- `retry` and `fix` are async, exactly like a normal dispatch: they print `DISPATCHED <new-run-id>` within seconds and your exec ends there. Do **not** wait, poll, or re-run them. The completion summary and CI verdict arrive by themselves as messages in the project thread.
- At dispatch time you know only the new run id. **Never state or guess which model or tier is running** — claiming one before the completion message arrives is fabrication.
- Never invent a run id. If the operator refers to a run you cannot identify, run `list` and ask which one.
- This skill never merges. A green PR still goes through the PR gate (`/gate`), which re-verifies every gate at the moment the operator approves.
- `go` is the one new-work dispatch this skill performs, and only against a work order the agent already staged and showed you — the review gate is unchanged (you read the work order before tapping). *Composing* new work is not part of this skill: the agent stages it (`edge-coder-run.sh stage '<task>'`) as part of `propose`. Free-form dispatch stays the explicit `edge-coder-run.sh '<task>'` step with the project's own config.
- Relay the script's stdout faithfully, in plain language. If it exits non-zero, say what it refused and why rather than retrying with a different id.
