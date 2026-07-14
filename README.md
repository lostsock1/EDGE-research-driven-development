# EDGE — Evidence-Driven Git Engineering

**A complete, battle-tested scaffolding for running an autonomous research → implementation → PR pipeline from a chat thread, on your own server, with a human holding the only merge button.**

[![template-ci](https://github.com/lostsock1/EDGE-evidence-driven-git-engineering/actions/workflows/ci.yml/badge.svg)](https://github.com/lostsock1/EDGE-evidence-driven-git-engineering/actions/workflows/ci.yml)
![Runs on](https://img.shields.io/badge/runs%20on-OpenClaw%20%2B%20opencode-blueviolet)
![Extracted from](https://img.shields.io/badge/extracted%20from-production-success)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen)](LICENSE)

One Telegram thread. A research agent (**EDGE**, running in [OpenClaw](https://openclaw.ai), animated by the **FRONTIER** persona — a truth-seeking operating philosophy that pre-registers its experiments and prizes refutation over confirmation) that studies your project, drafts work orders, and asks for your *go*. A coder team (**code-monkeys**, running in [opencode](https://opencode.ai)) that implements on feature branches and opens PRs. GitHub branch protection + CI as the mechanical quality gate. You read a plain-language summary on your phone and tap **merge** — in the GitHub UI, or right in the thread on a **PR-gate approval button** (the agent executes the merge, but only after your tap).

```text
you (Telegram) ──"go"──▶ EDGE ──dispatch──▶ wrapper ──tier ladder──▶ coder ──▶ PR
      ▲                                       │                                │
      │◀── plain-lingo summary + options ─────┘◀── ✅ done (effort/branch/PR) ───┤
      │◀────────────────────────────────────────── ✅ CI green, ready to merge ─┘
      └── you approve — merge on GitHub, or one tap on the gate's ✅ button
          (approval stays yours; the agent only executes it)
```

This template is extracted from a production setup running commercial-grade software development through this exact loop. Every guard in it exists because the unguarded version failed at least once.

## Contents

- [Workspace-first design](#workspace-first-design)
- [What's in the box](#whats-in-the-box)
- [The five ideas that make it work](#the-five-ideas-that-make-it-work)
- [The PR gate: approve merges with one tap](#the-pr-gate-approve-merges-with-one-tap)
- [Two tracks: what ships vs. the north star](#two-tracks-what-ships-vs-the-north-star)
- [The personality: FRONTIER](#the-personality-frontier)
- [Quickstart](#quickstart)
- [Daily driving](#daily-driving)
- [Hard-won lessons baked in](#hard-won-lessons-baked-in)
- [Safety posture](#safety-posture)
- [Documentation](#documentation)
- [License](#license)

## Workspace-first design

The EDGE control plane lives in one workspace directory (`~/.openclaw/workspace-${AGENT_ID}/`); project git checkouts live separately at each `RDD_REPO_DIR`:

```
~/.openclaw/workspace-edge/
├── SOUL.md, AGENTS.md, HEARTBEAT.md, ...    (workspace docs)
├── personas/                                (FRONTIER, AGAINST, INFINITY, BAYESIAN)
├── templates/                               (north-star-spec.md, etc.)
├── projects/<slug>/                         (EDGE charter/resume/notes; never the repo clone)
├── config/edge-rdd/config.env               (shared models/timeouts/variant policy)
├── config/edge-rdd/<slug>.env               (project repo/chat/branch/check identity)
├── config/edge-rdd/research.env             (OpenScience research dispatch)
├── config/edge-rdd/gate.env                 (PR gate hub)
├── config/opencode/agents/code-monkeys/     (coder, reviewer, _shared)
├── skills/gate/SKILL.md                     (/gate command)
├── skills/research/SKILL.md                 (/research command)
└── scripts/                                 (dispatch + PR gate + research scripts)
```

System paths (`~/.config/edge-rdd`, `~/.openclaw/skills/gate`, etc.) are symlinked to the workspace, so the runtime finds them without special configuration. **Single source of truth, easy backup, easy migration.**

## What's in the box

| Piece | File(s) | What it does |
|---|---|---|
| **Dispatch wrapper** | `scripts/edge-coder-run.sh` | The heart. Async dispatch with per-repo locking, an **ordered model-fallback ladder** (opencode has none natively) with per-tier **liveness probes**, an **effort policy** (auto-classified fast/standard/deep/max, per-tier variant maps, `[effort=…]` prefixes), failure classification (probe-fail/rate-limit/quota/auth/…), **partial-work handoff** between tiers, machine-readable completion trailer (model-reported; missing trailer/PR is disclosed explicitly; commitless/docs-only runs may complete without a PR), automatic completion + CI-verdict push to your chat thread, and a CI-green → gate-sweep trigger |
| **Research companion** | `openscience/`, `openclaw/skills/research/`, `scripts/openscience-*` | Optional second oracle: a local, systemd-hardened, **research-only** OpenScience workbench driven by the `/research` skill — async packets with Accept/Reject buttons, a per-project knowledge base, and the [dual-research protocol](docs/research-protocol.md). Bring your own models |
| **Coder agents** | `opencode/agents/code-monkeys/` | Primary coder + independent read-only reviewer + shared doctrine. Permission maps tuned for **non-interactive** dispatch (no `ask` traps), with hard denies on merges, force-pushes, and secrets |
| **Research agent** | `openclaw/agent.edge.json5`, `openclaw/topic.project-thread.json5` | OpenClaw agent definition + Telegram topic binding with the full async-dispatch operating instructions baked into the system prompt |
| **Agent workspace** | `workspace-edge/` | Project charter (the 10-point evidence-driven engineering operating loop) + the plain-lingo **communication contract** + RESUME.md restart packet |
| **North-star doc + validator** | `workspace-edge/SUPERIOR_ARCHITECTURE.md`, `scripts/validate-superior-architecture.py` | The theoretical best-known architecture, seeded per project **outside** the repo — fed by external research *and* the project's own internal evidence (evals/ADRs/experiments/reality-feedback), distilled to hardware-independent mechanism, promoted into the repo only through the staging pipeline. The unconstrained design track that pulls the roadmap forward without ever blurring into it |
| **North-star spec template** | `workspace-edge/templates/north-star-spec.md` | The prompt template the operator uses at kickoff to generate a project's dense **north-star specification** — the authoritative product definition the research agent distills the Mission and Superior Architecture from. Full 28-section prompt, a self-contained short variant, and composable technical/product/adversarial add-ons |
| **Note templates** | `workspace-edge/templates/` | Five additional Obsidian-compatible templates (daily note, inbox note, project, research note) — deployed by install.sh and refreshed on every apply |
| **Workspace docs** | `workspace-edge/AGENTS.md`, `workspace-edge/IDENTITY.md`, `workspace-edge/SKILL-REGISTRY.md` | Comprehensive workspace guide (persona system, project kickoff, install/portability, skill registry), stable identity card, skill tracking framework — seeded by install.sh, never overwritten |
| **Persona marker** | `PERSONA.md` | Non-loaded copy of the active persona — regenerated by install.sh to match `SOUL.md` on every apply |
| **Persona library** | `workspace-edge/personas/` | Four swappable operating philosophies for the research agent — **FRONTIER v2.1** (default, seeded into `SOUL.md`; see [The personality](#the-personality-frontier)), AGAINST, INFINITY, BAYESIAN — with the activation mechanism documented (copy over `SOUL.md`; a `PERSONA.md` marker does nothing) |
| **Repo handoff docs** | `project-repo/docs/agent/` | The git-tracked protocol both sides read: `PROJECT_STATE` · `TASKS` · `QUALITY_GATES` · `KNOWLEDGE_STAGING` · `RESEARCH_TRANSFER` · `EDGE_COLLABORATION` |
| **GitHub gate** | `github/protect-branch.sh`, `project-repo/.github/workflows/ci.yml.example` | One-command branch protection (required checks, up-to-date branch, no force-push, admins included, 0 approvals — *you* are the approval) |
| **PR gate** | `scripts/edge-pr-gate.sh` | Run `/gate sweep` to check every project repo — green PRs, CI verdicts, stray branches — and post **one-tap approval buttons** (per item, plus **Do-all**), each with a what/consequence/why brief, into **one gate thread**. You tap ✅ (or react 👍, or type `/gate`), the agent re-verifies and executes the merge / branch cleanup, and every repo converges back to **trunk-only**. See [The PR gate](#the-pr-gate-approve-merges-with-one-tap) |
| **Installer** | `install.sh`, `uninstall.sh`, `template.env.example` | Workspace-first install: keeps the repo checkout separate from EDGE notes, creates symlinks, and generates shared `config.env`, per-project `<slug>.env`, `gate.env`, and `research.env`. Uninstall with `--purge` (keeps repos) or `--purge-all` (removes everything) |
| **Thread bootstrap** | `scripts/kickoff.sh`, `messages/` | One-shot first-boot handshake: **preflights the GitHub connection** (gh auth, reachable repo, matching clone, protection), then posts the development-kickoff + pinnable **command palette** into the project thread |

## The five ideas that make it work

1. **Files are the protocol, chat is the trigger.** Work orders, promoted research, research requests, and reality feedback live in git-tracked docs both runtimes read. The loop survives restarts, context compaction, and model swaps.
2. **Research and implementation never blur.** The research agent cannot touch git; the coder cannot originate architecture decisions. Each hands off through explicit, templated documents — including *reality feedback* when a proposal loses to the real codebase (the anti-hallucination loop).
3. **The human gate is mechanical.** Agents physically cannot push to the trunk — GitHub rejects it. Everything lands as a PR with green required checks, and nothing merges without the operator's explicit approval — in the GitHub UI, or with one tap on a [PR-gate button](#the-pr-gate-approve-merges-with-one-tap) (the agent executes, but only after your tap). This is why agent permissions can be permissive enough to actually work unattended.
4. **Fallback is owned, visible, and resumable.** The wrapper's model tier ladder probes each tier before trusting it, classifies every failure (a `fallback path: model-a: rate-limited → model-b` line in the completion message), and hands a failed tier's partial work to the next tier with "continue, don't restart".
5. **Trust nothing you can verify.** The wrapper checks the completion trailer mechanically, resolves branch/commits/PR from git itself, and posts what actually happened — not what the model claims happened.

## The PR gate: approve merges with one tap

The loop ends at a human decision — but that decision shouldn't require opening GitHub. Run `/gate sweep` (or just `gate sweep` in chat) — `scripts/edge-pr-gate.sh sweep` checks **every** configured project — projects are simply the `*.env` files in `~/.config/edge-rdd/`, the same ones the dispatch wrapper reads, so there is no second registry to drift — and for each repo looks at:

- **open PRs** and their strict CI verdict (every check green, every per-project `RDD_REQUIRED_CHECKS` context present/pass; no-CI is never chat-mergeable), plus the current-head reviewer marker,
- **every non-trunk branch**, classified: active PR head · leftover of a merged/closed PR · orphan with or without unique commits.

Anything actionable — a green PR ready to merge, a stale branch to prune — becomes a **single-use pending action**, and the sweep posts one approval message per project into **one gate thread** (`RDD_GATE_TG_*` in `workspace/config/edge-rdd/gate.env` — point it at your EDGE coordination thread so every project's asks land in one place instead of scattered across per-project threads). Each ask carries an inline button per action **and a plain-language brief: what the action does, its consequence, and why it's being offered** — so you're never approving a bare button. A snooze button rides along; unchanged asks are not re-posted for 24h; a clean project posts nothing. The declared goal is **trunk-only repos**: merged work in, dead branches gone.

**Approving is one tap.** A button tap delivers a native command (`/gate act eg:<id>`) to the research agent. A 👍/✅ reaction on the gate message — or replying "approve" — works too (`pending` resolves which action; if it's ambiguous the agent asks). `act` then **re-verifies at execution time** — the PR is still open against the protected trunk, its head and trunk-base SHAs still match the approved snapshot, strict checks and trusted-author reviewer marker still pass, or the branch is still stale — and only then executes (`gh pr merge --squash --delete-branch`, or a remote branch delete), posts the outcome back, and burns the action id.

**What did NOT change:** nothing merges without your explicit approval. The approval surface moved from the GitHub UI to a button in your chat; the executor moved from your thumb to the agent — *after* your tap. Actions are minted only by the sweep from observed repo state, are single-use, re-verify before executing (a stale button can never merge a PR whose CI went red), and the agent is under doctrine to never run `gh pr merge` or delete branches outside `act`. Red, pending, missing-required-check, no-CI, and reviewer-blocked PRs are never offered as actions — they ride the normal `fix the red PR` loop.

**Clear a whole project in one tap.** When a project has two or more pending items, the ask also carries a **"☑️ Do all N of the above"** button. Approving it runs every pending action for that project at once — each still independently re-verified before it executes, so a batch approval can never force through a PR that has since gone red.

**Trigger it yourself with `/gate`.** The gate ships as a slash command (the `gate` skill): `/gate` (or `/gate sweep`) runs a sweep now, `/gate pending` lists open asks, `/gate status` shows recent results, `/gate act <id>` executes an approved action. Plain `gate sweep` / `gate pending` phrasing works too. Dry-run everything with `edge-pr-gate.sh sweep --dry-run`.

## Two tracks: what ships vs. the north star

The loop keeps **two parallel artifacts** and never blurs them:

- **The roadmap** (`docs/agent/ROADMAP.md`, `TASKS.md`, in the repo) — what can ship *now*, under the real deployment's constraints.
- **The north star** (`workspace-edge/SUPERIOR_ARCHITECTURE.md`, seeded per project into `projects/<slug>/notes/`) — the theoretical *best* architecture, under realistic-but-generous hardware with full model access, held **outside** the repo.

The track starts with the **operator's north-star spec** — a dense product definition generated at kickoff from `workspace-edge/templates/north-star-spec.md`, landed verbatim (`status: unprocessed`) in `projects/<slug>/notes/` and distilled by the research agent into the charter Mission and the Superior Architecture doc. Raw spec sections are never work orders.

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
# 1. Clone template
git clone https://github.com/lostsock1/EDGE-evidence-driven-git-engineering
cd EDGE-evidence-driven-git-engineering

# 2. Configure
cp template.env.example template.env
$EDITOR template.env

# 3. Render (safe, review)
./install.sh

# 4. Apply (creates workspace, symlinks, clones repo)
./install.sh --apply

# 5. Manual steps (printed by install.sh)
# - Merge rendered/openclaw/agent.edge.json5 into ~/.openclaw/openclaw.json
# - Merge rendered/openclaw/topic.project-thread.json5 into Telegram topics
# - openclaw config validate && systemctl --user restart openclaw-gateway
# - Copy CI workflow into project repo
# - bash github/protect-branch.sh
# - bash scripts/kickoff.sh
```

Then follow **[docs/SETUP.md](docs/SETUP.md)** for the OpenClaw merge, CI, branch protection, and the smoke test. Read **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for the why behind every design decision, and **[docs/OPERATIONS.md](docs/OPERATIONS.md)** for daily driving and troubleshooting.

### Requirements

Linux server · [OpenClaw](https://docs.openclaw.ai) gateway with a Telegram channel · [opencode](https://opencode.ai) with keys for ≥2 coder models · `gh` CLI authed on the project repo · `flock`, `setsid`, `jq`, `python3`.

### Adding a second project

```bash
# 1. Clone the repo
git clone https://github.com/you/newproject ~/projects/NewProject

# 2. Create project-identity config (shared model policy is inherited)
cp ~/.openclaw/workspace-edge/config/edge-rdd/myproject.env \
   ~/.openclaw/workspace-edge/config/edge-rdd/newproject.env
# Edit every identity field: RDD_PROJECT_NAME/SLUG, RDD_REPO_SLUG/DIR,
# RDD_TG_TARGET/THREAD, RDD_DOCS_DIR, RDD_MAIN_BRANCH, RDD_REQUIRED_CHECKS

# 3. Create notes directory
mkdir -p ~/.openclaw/workspace-edge/projects/newproject/notes/

# Gate picks it up automatically (scans config/edge-rdd/*.env)
```

### Uninstalling

```bash
./uninstall.sh              # remove symlinks only (safe, reversible)
./uninstall.sh --purge      # remove runtime workspace, preserve EDGE project notes
./uninstall.sh --purge-all  # remove the entire EDGE workspace (external repos stay untouched)
```

## Daily driving

| You type | What happens |
|---|---|
| `research <link>` | EDGE distills it to mechanisms and stages what changes implementation |
| `propose` | best staged finding becomes a work order, posted for your approval |
| `go` | `DISPATCHED run-…` in seconds; ✅ completion + CI verdict arrive on their own |
| `sweep` | GitHub hygiene: open PRs, stale branches, failed runs, doc drift |
| `gate sweep` | run the PR gate now — approval buttons for green PRs / stale branches |
| `gate pending` | list open gate asks; tap a button, react 👍, or say "approve" to execute one |
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

Permissions stay **ON** everywhere — `--dangerously-skip-permissions` is forbidden by doctrine and unnecessary by design. Secrets (`.env*`, `**/secrets/**`, `**/.ssh/**`, `**/credentials/**`) are hard-denied at read *and* edit level in every agent. Merges, releases, force-pushes, and history rewrites are denied to agents and rejected by GitHub. Elevated chat-exec is allowlisted to the operator's own account id only. The PR gate does not weaken this: a merge still requires the operator's explicit tap, executes only through single-use, re-verified gate actions, and the coder agents' own merge denies stay in place.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | End-to-end install: OpenClaw merge, CI, branch protection, kickoff, smoke test |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The why behind every design decision — including the known traps, learned the hard way |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Daily driving, command reference, troubleshooting |
| [docs/research-protocol.md](docs/research-protocol.md) | The dual-research protocol for the OpenScience companion |

## License

[MIT](LICENSE)
