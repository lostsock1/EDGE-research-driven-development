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
        │  effort classified (auto) → tier 1 probe ── fail? next tier …
        │  tier 1 model ── fail? classify reason, hand off partial work ──▶ tier 2 …
        ▼
 opencode code-monkeys/coder  (permissions ON)
        │  branch cm/<slug> ── commits ── push ── PR to trunk
        │  non-trivial? -> dispatch reviewer (read-only verdict)
        │  hits research boundary? -> file request in EDGE_COLLABORATION.md + STOP
        ▼
 wrapper loop closer
        │  verify trailer · resolve PR · collect commits · detect open requests
        ├──▶ Telegram: ✅ completion summary (effort, variant, branch, PR, trailer, commits)
        └──▶ CI watcher (detached): polls gh pr checks; green also auto-triggers a gate sweep
                 └──▶ Telegram: CI + reviewer gate verdict / ❌ blockers
        ▼
 operator explicitly approves in GitHub or via a single-use chat-gate action
        ▼
 EDGE post-merge: tick TASKS.md, update RESUME.md, answer open requests
```

## Design decisions and why

**Async dispatch, not blocking.** The research agent's `exec` has a timeout budget; a long coding run would behead it. The wrapper detaches a worker (which inherits the flock fd, so there is no unlocked gap) and pushes results back into the thread when they exist. The agent's instructions say: relay `DISPATCHED <id>`, end the turn, never poll.

**The wrapper owns model fallback, because opencode doesn't.** opencode has no native retry-on-429 and no provider fallback. The tier ladder (`RDD_MODELS` in `~/.config/edge-rdd/config.env` — the single source of truth) is the fallback layer. Each tier first answers a tiny **liveness probe** inside its per-tier `RDD_TIMEOUTS_*` budget — a dead key, hung provider, or 429 fails over in seconds instead of consuming an hour-long task timeout — then gets a fixed work budget for the real task. Failures are **classified** (probe-fail / rate-limited / quota / auth / overloaded / timeout) so a fallback is never silent, and **partial-work handoff** describes a failed tier's commits and dirty tree to the next tier with "continue, don't restart". An optional **effort policy** (`RDD_VARIANT_POLICY=auto`) classifies each task (fast/standard/deep/max) and applies per-tier opencode variant maps you define — task prefix `[effort=…]` overrides it. The full JSON stream of every run is tee'd to an immutable per-run `runs/<run-id>.stream.log`; streams are never shared across dispatches and expire after seven days.

**`ask` permissions are a trap in non-interactive dispatch.** There is no human at the opencode prompt, so `ask` auto-rejects and beheads the run mid-task (we lost a real run to an ADR edit gated `ask`). The template therefore uses **only `allow` and `deny`**: the coder gets broad bash `allow` with hard denies on history rewrite, force-push, merges, releases, and privilege escalation; the reviewer gets broad read `allow` with an explicit deny-list on every write/network verb. The safety this seems to give up is re-provided mechanically one layer down:

**The human gate is branch protection, not agent obedience.** Agents *cannot* push to the trunk — GitHub rejects it regardless of what any prompt says. PRs require the configured green required checks and an up-to-date branch; `enforce_admins` is on; force pushes and deletions are off; approvals are set to 0 because the operator pressing "merge" *is* the approval. `gh pr merge` / `git push --force` / `git reset` stay hard-`deny` in the agent permission maps as a second layer.

**The merge tap can live in the chat without weakening the gate.** The PR gate (`edge-pr-gate.sh`) moves the approval *surface* to a thread button while keeping the approval *authority* with the operator: actions are minted only by the sweep from observed GitHub state, are single-use and head/base-SHA-bound, and `act` re-verifies the preconditions at execution time (PR still open against the protected trunk, approved head unchanged, every check green, every per-project named context present/pass, current-head reviewer marker authored by the authenticated gate account eligible, branch still stale) — so a stale button can never merge changed or red work. The research agent is under doctrine to never merge or delete branches outside `act`; the coder agents keep their hard `deny` on merges either way. The sweep's second job is entropy control: repos converge to trunk-only because every merged/orphaned branch gets offered for pruning.

**A machine-readable trailer, mechanically verified within its trust limit.** Every coder run must end with `=== LOOP STATUS ===` (branch, commits, PR, reviewer verdict, open research requests, tests). The wrapper parses the reviewer verdict and persists a current-head marker; non-trivial Fail/not-run/missing verdicts are not gate-ready. Coder and reviewer share one runtime/GitHub identity, so this is enforced model-reported evidence—not an independent security boundary. Branch/base SHAs, PR state, and CI facts are independently resolved from git/GitHub.

**Files, not chat, are the protocol.** Work orders (`TASKS.md`), promoted research (`RESEARCH_TRANSFER.md`), research requests and reality feedback (`EDGE_COLLABORATION.md`), and current state (`PROJECT_STATE.md`) are git-tracked files both runtimes read. Chat is for dispatch, nudges, and human decisions. This is what makes the loop survive restarts, compactions, and model swaps.

**Promotion rule (anti-hallucination).** Raw research never becomes a coding instruction. It must pass the staging ladder (raw → extracted → candidate → proposed → accepted → tasked) and land in an execution doc first. In the other direction, coders must send **reality feedback** when a proposal meets the real code and loses — naming the failed assumption, so the research agent learns instead of repeating it.

**A north star, kept off the ship-it track.** The track begins with the operator's **north-star spec** — a dense product definition generated at kickoff from `workspace-edge/templates/north-star-spec.md`, landed verbatim and unprocessed in `projects/<slug>/notes/`. The research agent maintains a living *Superior Architecture* doc per project (`workspace-edge/SUPERIOR_ARCHITECTURE.md`, seeded into `projects/<slug>/notes/`) — the theoretical best-known design under realistic-but-generous hardware with full model access, synthesized from that spec and held **outside** the repo. It is fed by two inputs at once: external research and the project's own internal evidence (evals, ADRs, contained experiments, coder reality-feedback), each distilled to the mechanism truth that survives on any hardware. It is deliberately unconstrained by the current deployment target, so it can pull the roadmap forward instead of merely rationalizing it; findings cross into the repo only as gated slot-replacement packets, and implementation reality flows back into it. A portable validator blocks missing/inconsistently named specs, scaffold prose, unresolved source indexes, missing local evidence files, absent local-evidence hashes, absent versions, expired synthesis, and input hash drift. It cannot prove human authorship: heartbeat synthesis requires an explicit operator-supplied authority attestation that agents are forbidden to create. It never invents a product definition. This keeps "what we can ship now" and "what the best design is" as two honest, separately-versioned tracks rather than one muddled roadmap — the same reason research and implementation never blur.

**Frozen decision rules.** For any performance/quality claim, the pass/fail gate is written down *before* measuring, and negative results are recorded. This keeps an autonomous research loop honest — no post-hoc threshold tuning, no silent discarding of refutations.

**One dispatch at a time, per repo.** A per-repo `flock` refuses concurrent dispatches (with holder info), because two coders in one working tree corrupt each other's partial work. The CI watcher closes its inherited lock fd so the *next* dispatch isn't blocked while checks run.

**Contained experiments in Docker, not the agent sandbox.** EDGE no longer runs experiments directly in its `exec` environment. Every experiment launches in an ephemeral Docker container via `lab/lab-run.sh` — fully air-gapped (`--network none`), resource-bounded (memory/CPU/timeout), mounted read/write only on the experiment directory, and auto-destroyed on completion (`--rm`). The container image (`edge-gapped-lab`) ships Python 3.12 + numpy/pandas/scipy/scikit-learn + git/curl/jq. The pre-registration protocol (hypothesis, rival, refutation_condition) is enforced mechanically — `lab-run.sh` refuses to run without a filled `protocol.yaml`. This turns the persona's "gapped lab" from a discipline into a mechanism. See `lab/README.md` for usage.

## Experiment layers (three oracles)

EDGE tests ideas through three separate oracles, ordered by the strength of evidence they provide:

1. **Gapped lab** (`lab/lab-run.sh`) — EDGE designs the test. Ephemeral Docker container, pre-registered protocol, air-gapped, auto-destroyed. Weakest evidence (EDGE can shape the test) but cheapest and fastest.
2. **Implementation oracle** (`edge-coder-run.sh`) — Reality designs the test. A coder agent implements the work order on a feature branch; the seam that wasn't there, the test that failed, the interface that didn't fit — these are refutations EDGE couldn't shape. Highest-grade evidence.
3. **OpenScience** (`openscience-research.sh` + the `/research` skill) — External research sandbox: a local, systemd-hardened, research-only workbench (see `openscience/README.md`). Async packets return to the originating thread with Accept/Reject buttons; accepted packets land in the workspace projects tree (`projects/<project>/notes/`), where the Superior Architecture validator can hash-bind them as evidence. Feeds the research pool with mechanisms from papers and repos, and pairs with the agent's own web research under the dual-research protocol (`docs/research-protocol.md`).

A finding promotes: lab survival → implementation survival → merged and proven.

## Known traps (learned the hard way, guarded by the template)

- A stray `.git` at `$HOME` makes opencode snapshot-walk the entire home directory and hang forever. The wrapper refuses to dispatch while it exists.
- A user-pinned session model in OpenClaw (`/model` in chat) silently disables the agent's **entire** fallback chain; a 429 then surfaces as a hard error. Clear stale pins from the agent's `sessions.json` (gateway stopped) if failover "mysteriously" stops working.
- CI workflows that still trigger on a deleted/renamed branch run never — and nobody notices until a bad merge. Re-check `on.push.branches` whenever the trunk changes.
- Required check contexts must exactly equal CI job names; a renamed job blocks every PR forever.
