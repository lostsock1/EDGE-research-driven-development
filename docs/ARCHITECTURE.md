# Architecture

## The one-paragraph version

A **research agent** (EDGE, running in OpenClaw, driven from a Telegram thread) continuously researches your project and turns findings into promoted work orders. A **coder team** (code-monkeys, running in opencode) implements those work orders on feature branches and opens PRs. GitHub branch protection + CI form the mechanical quality gate; the **human operator** is the only one who can merge. Every hop between the three parties is either a git-tracked file or an automated chat message — nothing lives only in a chat scrollback.

## Roles

| Party | Runtime | Owns | Never does |
|---|---|---|---|
| Operator | Telegram | direction, "go" decisions, merges | write code directly |
| EDGE | OpenClaw agent | research, ADRs, work orders, repo hygiene watch | touch repo git; merge |
| code-monkeys/coder | opencode | implementation, tests, git, PRs | originate architecture decisions; merge |
| code-monkeys/reviewer | opencode subagent | independent read-only review | modify files, push |
| GitHub | — | branch protection, CI, PR state | — |

## Message/artifact flow

```text
 Telegram project thread (operator <-> EDGE)
        │  operator: "go" on a posted work order
        ▼
 EDGE: exec edge-coder-run.sh '<promoted task>'      (async, ~1s)
        │  returns: DISPATCHED <run-id>
        ▼
 wrapper (detached worker, per-repo flock)
        │  tier 1 model ── fail? classify reason, hand off partial work ──▶ tier 2 …
        ▼
 opencode code-monkeys/coder  (permissions ON)
        │  branch cm/<slug> ── commits ── push ── PR to trunk
        │  non-trivial? -> dispatch reviewer (read-only verdict)
        │  hits research boundary? -> file request in EDGE_COLLABORATION.md + STOP
        ▼
 wrapper loop closer
        │  verify trailer · resolve PR · collect commits · detect open requests
        ├──▶ Telegram: ✅ completion summary (model, branch, PR, trailer, commits)
        └──▶ CI watcher (detached): polls gh pr checks
                 └──▶ Telegram: ✅ "all green — ready for human merge" / ❌ failed checks
        ▼
 operator merges on GitHub (the only unprotected write path)
        ▼
 EDGE post-merge: tick TASKS.md, update RESUME.md, answer open requests
```

## Design decisions and why

**Async dispatch, not blocking.** The research agent's `exec` has a timeout budget; a long coding run would behead it. The wrapper detaches a worker (which inherits the flock fd, so there is no unlocked gap) and pushes results back into the thread when they exist. The agent's instructions say: relay `DISPATCHED <id>`, end the turn, never poll.

**The wrapper owns model fallback, because opencode doesn't.** opencode has no native retry-on-429 and no provider fallback. The tier ladder (`RDD_MODELS`) is the fallback layer, with per-tier hard timeouts, failure **classification** (rate-limited / quota / auth / overloaded / timeout) so a fallback is never silent, and **partial-work handoff** — a failed tier's commits and dirty tree are described to the next tier with "continue, don't restart".

**`ask` permissions are a trap in non-interactive dispatch.** There is no human at the opencode prompt, so `ask` auto-rejects and beheads the run mid-task (we lost a real run to an ADR edit gated `ask`). The template therefore uses only `allow` and `deny` for routine dev surfaces, and keeps `ask` solely for things that should genuinely never happen unattended (network fetches to arbitrary hosts, `docker compose up`, outbound messages). The safety this seems to give up is re-provided mechanically one layer down:

**The human gate is branch protection, not agent obedience.** Agents *cannot* push to the trunk — GitHub rejects it regardless of what any prompt says. PRs require green required checks and an up-to-date branch; `enforce_admins` is on; force pushes and deletions are off; approvals are set to 0 because the operator pressing "merge" *is* the approval. `gh pr merge` / `git push --force` / `git reset` stay hard-`deny` in the agent permission maps as a second layer.

**A machine-readable trailer, mechanically verified.** Every coder run must end with `=== LOOP STATUS ===` (branch, commits, PR, reviewer verdict, open research requests, tests CI can't run). The wrapper greps for it and flags `trailer: MISSING` rather than trusting model adherence — and independently resolves branch/commits/PR from git and `gh`, so the completion message is true even when the model's report isn't.

**Files, not chat, are the protocol.** Work orders (`TASKS.md`), promoted research (`RESEARCH_TRANSFER.md`), research requests and reality feedback (`EDGE_COLLABORATION.md`), and current state (`PROJECT_STATE.md`) are git-tracked files both runtimes read. Chat is for dispatch, nudges, and human decisions. This is what makes the loop survive restarts, compactions, and model swaps.

**Promotion rule (anti-hallucination).** Raw research never becomes a coding instruction. It must pass the staging ladder (raw → extracted → candidate → proposed → accepted → tasked) and land in an execution doc first. In the other direction, coders must send **reality feedback** when a proposal meets the real code and loses — naming the failed assumption, so the research agent learns instead of repeating it.

**A north star, kept off the ship-it track.** The research agent maintains a living *Superior Architecture* doc per project (`workspace-edge/SUPERIOR_ARCHITECTURE.md`, seeded into `projects/<slug>/notes/`) — the theoretical best-known design under realistic-but-generous hardware with full model access, held **outside** the repo. It is fed by two inputs at once: external research and the project's own internal evidence (evals, ADRs, contained experiments, coder reality-feedback), each distilled to the mechanism truth that survives on any hardware. It is deliberately unconstrained by the current deployment target, so it can pull the roadmap forward instead of merely rationalizing it; findings cross into the repo only as gated slot-replacement packets, and implementation reality flows back into it. This keeps "what we can ship now" and "what the best design is" as two honest, separately-versioned tracks rather than one muddled roadmap — the same reason research and implementation never blur.

**Frozen decision rules.** For any performance/quality claim, the pass/fail gate is written down *before* measuring, and negative results are recorded. This keeps an autonomous research loop honest — no post-hoc threshold tuning, no silent discarding of refutations.

**One dispatch at a time, per repo.** A per-repo `flock` refuses concurrent dispatches (with holder info), because two coders in one working tree corrupt each other's partial work. The CI watcher closes its inherited lock fd so the *next* dispatch isn't blocked while checks run.

## Known traps (learned the hard way, guarded by the template)

- A stray `.git` at `$HOME` makes opencode snapshot-walk the entire home directory and hang forever. The wrapper refuses to dispatch while it exists.
- A user-pinned session model in OpenClaw (`/model` in chat) silently disables the agent's **entire** fallback chain; a 429 then surfaces as a hard error. Clear stale pins from the agent's `sessions.json` (gateway stopped) if failover "mysteriously" stops working.
- CI workflows that still trigger on a deleted/renamed branch run never — and nobody notices until a bad merge. Re-check `on.push.branches` whenever the trunk changes.
- Required check contexts must exactly equal CI job names; a renamed job blocks every PR forever.
