# EDGE — Evidence-Driven Git Engineering

**A complete, battle-tested scaffolding for running an autonomous research → implementation → PR pipeline from a chat thread, on your own server, with a human holding the only merge button.**

One Telegram thread. A research agent (**EDGE**, running in [OpenClaw](https://openclaw.ai), animated by the **FRONTIER** persona — a truth-seeking operating philosophy that pre-registers its experiments and prizes refutation over confirmation) that studies your project, drafts work orders, and asks for your *go*. A coder team (**code-monkeys**, running in [opencode](https://opencode.ai)) that implements on feature branches and opens PRs. GitHub branch protection + CI as the mechanical quality gate. You read a plain-language summary on your phone and tap **merge**.

```text
you (Telegram) ──"go"──▶ EDGE ──dispatch──▶ wrapper ──tier ladder──▶ coder ──▶ PR
      ▲                                       │                                │
      │◀── plain-lingo summary + options ─────┘◀── ✅ done (model/branch/PR) ───┤
      │◀────────────────────────────────────────── ✅ CI green, ready to merge ─┘
      └── merge on GitHub (the only unprotected write path is yours)
```

This template is extracted from a production setup running commercial-grade software development through this exact loop. Every guard in it exists because the unguarded version failed at least once.

## What's in the box

| Piece | File(s) | What it does |
|---|---|---|
| **Dispatch wrapper** | `scripts/edge-coder-run.sh` | The heart. Async dispatch with per-repo locking, an **ordered model-fallback ladder** (opencode has none natively), per-tier timeouts, failure classification (rate-limit/quota/auth/…), **partial-work handoff** between tiers, mandatory machine-readable completion trailer, automatic completion + CI-verdict push to your chat thread |
| **Coder agents** | `opencode/agents/code-monkeys/` | Primary coder + independent read-only reviewer + shared doctrine. Permission maps tuned for **non-interactive** dispatch (no `ask` traps), with hard denies on merges, force-pushes, and secrets |
| **Research agent** | `openclaw/agent.edge.json5`, `openclaw/topic.project-thread.json5` | OpenClaw agent definition + Telegram topic binding with the full async-dispatch operating instructions baked into the system prompt |
| **Agent workspace** | `workspace-edge/` | Project charter (the 10-point evidence-driven engineering operating loop) + the plain-lingo **communication contract** + RESUME.md restart packet |
| **North-star doc** | `workspace-edge/SUPERIOR_ARCHITECTURE.md` | The theoretical best-known architecture, seeded per project **outside** the repo — fed by external research *and* the project's own internal evidence (evals/ADRs/experiments/reality-feedback), distilled to hardware-independent mechanism, promoted into the repo only through the staging pipeline. The unconstrained design track that pulls the roadmap forward without ever blurring into it |
| **Persona library** | `workspace-edge/personas/` | Four swappable operating philosophies for the research agent — **FRONTIER v2.1** (default, seeded into `SOUL.md`; see [The personality](#the-personality-frontier)), AGAINST, INFINITY, BAYESIAN — with the activation mechanism documented (copy over `SOUL.md`; a `PERSONA.md` marker does nothing) |
| **Repo handoff docs** | `project-repo/docs/agent/` | The git-tracked protocol both sides read: `PROJECT_STATE` · `TASKS` · `QUALITY_GATES` · `KNOWLEDGE_STAGING` · `RESEARCH_TRANSFER` · `EDGE_COLLABORATION` |
| **GitHub gate** | `github/protect-branch.sh`, `project-repo/.github/workflows/ci.yml.example` | One-command branch protection (required checks, up-to-date branch, no force-push, admins included, 0 approvals — *you* are the approval) |
| **Installer** | `install.sh`, `template.env.example` | Fill one env file, render, review, `--apply` with automatic backups |
| **Thread bootstrap** | `scripts/kickoff.sh`, `messages/` | One-shot first-boot handshake: **preflights the GitHub connection** (gh auth, reachable repo, matching clone, protection), then posts the development-kickoff + pinnable **command palette** into the project thread |

## The five ideas that make it work

1. **Files are the protocol, chat is the trigger.** Work orders, promoted research, research requests, and reality feedback live in git-tracked docs both runtimes read. The loop survives restarts, context compaction, and model swaps.
2. **Research and implementation never blur.** The research agent cannot touch git; the coder cannot originate architecture decisions. Each hands off through explicit, templated documents — including *reality feedback* when a proposal loses to the real codebase (the anti-hallucination loop).
3. **The human gate is mechanical.** Agents physically cannot push to the trunk — GitHub rejects it. Everything lands as a PR with green required checks, and only the operator merges. This is why agent permissions can be permissive enough to actually work unattended.
4. **Fallback is owned, visible, and resumable.** The wrapper's model tier ladder classifies every failure (`rate-limited → deepseek-v4-pro` in the completion message), and a failed tier's partial work is handed to the next tier with "continue, don't restart".
5. **Trust nothing you can verify.** The wrapper checks the completion trailer mechanically, resolves branch/commits/PR from git itself, and posts what actually happened — not what the model claims happened.

## Two tracks: what ships vs. the north star

The loop keeps **two parallel artifacts** and never blurs them:

- **The roadmap** (`docs/agent/ROADMAP.md`, `TASKS.md`, in the repo) — what can ship *now*, under the real deployment's constraints.
- **The north star** (`workspace-edge/SUPERIOR_ARCHITECTURE.md`, seeded per project into `projects/<slug>/notes/`) — the theoretical *best* architecture, under realistic-but-generous hardware with full model access, held **outside** the repo.

The north star is deliberately unconstrained by the current hardware, so it pulls the roadmap forward instead of rationalizing it. It is a **two-input synthesis** — external research *and* the project's own internal evidence (evals, ADRs, contained experiments, coder reality-feedback), each distilled to the **mechanism truth that survives on any hardware** (hardware/latency/cost limits stay in the repo docs, cited in the north star only where they reveal a mechanism, never as a constraint). Findings cross into the repo only as gated slot-replacement packets through the staging pipeline; implementation reality flows back in; and when a mechanism is built and proven, that is recorded as evidence the design is real. Created at kickoff, maintained by the research agent, versioned with an evidence-weighted changelog — one honest record of "the best design we can currently defend," kept separate from "what we shipped."

## The personality: FRONTIER

The pipeline's mechanics assume a research agent that *wants* to refute its own ideas — that disposition is supplied by **FRONTIER** (`workspace-edge/personas/FRONTIER.md`, v2.1), the default persona seeded into the agent's `SOUL.md` and injected into every session.

**The engine:** two ways to create novelty — *assembly* (absorb the working mechanisms from papers, repos, and adjacent fields, then recombine them into a new hard-to-vary whole) and *spark* (hunt the missing link whose absence blocks a whole region). Generation is anarchic (Feyerabend: proliferate rivals, counterinduce, no authority); evaluation is ruthless (Deutsch: one criterion — *hard to vary* — every detail load-bearing or deleted).

**The discipline:** every experiment is pre-registered **on disk** before it runs — hypothesis, rival, discriminating prediction, and the refutation condition that kills the favored idea; a recorded pre-commitment is a goalpost that can't quietly move. The persona also names the failure modes of the LLM running it — sycophantic convergence, confirmation in self-grading, confident out-of-distribution assertion, goalpost drift — each with its check.

**The loop interface (v2.1):** FRONTIER was rewired for exactly this pipeline —

- **Decisions bind action, not belief.** Frozen decision rules, accepted ADRs, and the operator's gates hold while they stand; they're challenged through the promotion path with new evidence, never re-litigated in passing.
- **Implementer reality-feedback is a second oracle** — refutation of the highest grade, *because the researcher couldn't shape the test*.
- **A dispatch is the most expensive experiment available**, so the work order *is* its pre-registration (ID, acceptance criteria, out-of-scope, frozen rule).
- **Clerk mode:** relays, sweeps, and doc updates get zero creativity — precision there buys the license to be radical everywhere else.
- **The null is a result.** "Nothing worth promoting" is valid, reportable output — an autonomous loop that must always find something starts confabulating on schedule (*manufactured cadence*, a named failure mode).

Three alternates ship alongside (AGAINST · INFINITY · BAYESIAN — see `workspace-edge/personas/README.md`); swap by copying over `SOUL.md`, or overlay a different persona on a single topic. Swapping changes how aggressively the research side criticizes itself — the mechanical gates (branch protection, CI, reviewer, human merge) hold regardless.

## Quickstart

```bash
git clone https://github.com/lostsock1/EDGE-evidence-driven-git-engineering
cd EDGE-evidence-driven-git-engineering
cp template.env.example template.env && $EDITOR template.env
./install.sh              # render only — review ./rendered/
./install.sh --apply      # install with automatic backups
bash scripts/kickoff.sh   # after the GitHub steps — verifies the repo connection,
                          # then posts the kickoff + pinnable command palette
```

Then follow **[docs/SETUP.md](docs/SETUP.md)** for the OpenClaw merge, CI, branch protection, and the smoke test. Read **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for the why behind every design decision, and **[docs/OPERATIONS.md](docs/OPERATIONS.md)** for daily driving and troubleshooting.

### Requirements

Linux server · [OpenClaw](https://docs.openclaw.ai) gateway with a Telegram channel · [opencode](https://opencode.ai) with keys for ≥2 coder models · `gh` CLI authed on the project repo · `flock`, `setsid`, `jq`, `python3`.

## Daily driving

| You type | What happens |
|---|---|
| `research <link>` | EDGE distills it to mechanisms and stages what changes implementation |
| `propose` | best staged finding becomes a work order, posted for your approval |
| `go` | `DISPATCHED run-…` in seconds; ✅ completion + CI verdict arrive on their own |
| `sweep` | GitHub hygiene: open PRs, stale branches, failed runs, doc drift |
| `status` | resume from disk, plain-language state of everything |

Every substantive reply follows the communication contract: **plain-lingo summary → your options with tradeoffs → one recommendation with the why** — technical depth after.

## Hard-won lessons baked in

- `ask` permissions **auto-reject** in non-interactive dispatch and behead runs mid-task — use `allow` + mechanical downstream gates, or `deny`. Never `ask` for routine dev surfaces.
- opencode has **no native retry or provider fallback** — if you don't own the tier ladder, a 429 is a dead run.
- A stray `.git` in `$HOME` makes opencode snapshot-walk your entire home directory and hang forever.
- A user-pinned session model in OpenClaw silently disables the **whole** fallback chain.
- CI that triggers on a renamed/deleted branch runs never — and looks exactly like passing.
- Required-check contexts must equal CI job names, or every PR blocks forever.

(Each of these cost a real debugging session. Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#known-traps-learned-the-hard-way-guarded-by-the-template).)

## Safety posture

Permissions stay **ON** everywhere — `--dangerously-skip-permissions` is forbidden by doctrine and unnecessary by design. Secrets (`.env*`, `**/secrets/**`, `**/.ssh/**`, `**/credentials/**`) are hard-denied at read *and* edit level in every agent. Merges, releases, force-pushes, and history rewrites are denied to agents and rejected by GitHub. Elevated chat-exec is allowlisted to the operator's own account id only.

## License

[MIT](LICENSE)
