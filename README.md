# EDGE — Research Driven Development

**A complete, battle-tested scaffolding for running an autonomous research → implementation → PR pipeline from a chat thread, on your own server, with a human holding the only merge button.**

One Telegram thread. A research agent (**EDGE**, running in [OpenClaw](https://openclaw.ai)) that studies your project, drafts work orders, and asks for your *go*. A coder team (**code-monkeys**, running in [opencode](https://opencode.ai)) that implements on feature branches and opens PRs. GitHub branch protection + CI as the mechanical quality gate. You read a plain-language summary on your phone and tap **merge**.

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
| **Agent workspace** | `workspace-edge/` | Project charter (the 10-point research-driven-development operating loop) + the plain-lingo **communication contract** + RESUME.md restart packet |
| **Persona library** | `workspace-edge/personas/` | Four swappable operating philosophies for the research agent — **FRONTIER** (Feyerabend × Deutsch recombinant-synthesis engine, the default, seeded into `SOUL.md`), AGAINST, INFINITY, BAYESIAN — with the activation mechanism documented (copy over `SOUL.md`; a `PERSONA.md` marker does nothing) |
| **Repo handoff docs** | `project-repo/docs/agent/` | The git-tracked protocol both sides read: `PROJECT_STATE` · `TASKS` · `QUALITY_GATES` · `KNOWLEDGE_STAGING` · `RESEARCH_TRANSFER` · `EDGE_COLLABORATION` |
| **GitHub gate** | `github/protect-branch.sh`, `project-repo/.github/workflows/ci.yml.example` | One-command branch protection (required checks, up-to-date branch, no force-push, admins included, 0 approvals — *you* are the approval) |
| **Installer** | `install.sh`, `template.env.example` | Fill one env file, render, review, `--apply` with automatic backups |

## The five ideas that make it work

1. **Files are the protocol, chat is the trigger.** Work orders, promoted research, research requests, and reality feedback live in git-tracked docs both runtimes read. The loop survives restarts, context compaction, and model swaps.
2. **Research and implementation never blur.** The research agent cannot touch git; the coder cannot originate architecture decisions. Each hands off through explicit, templated documents — including *reality feedback* when a proposal loses to the real codebase (the anti-hallucination loop).
3. **The human gate is mechanical.** Agents physically cannot push to the trunk — GitHub rejects it. Everything lands as a PR with green required checks, and only the operator merges. This is why agent permissions can be permissive enough to actually work unattended.
4. **Fallback is owned, visible, and resumable.** The wrapper's model tier ladder classifies every failure (`rate-limited → deepseek-v4-pro` in the completion message), and a failed tier's partial work is handed to the next tier with "continue, don't restart".
5. **Trust nothing you can verify.** The wrapper checks the completion trailer mechanically, resolves branch/commits/PR from git itself, and posts what actually happened — not what the model claims happened.

## Quickstart

```bash
git clone https://github.com/lostsock1/EDGE-research-driven-development
cd EDGE-research-driven-development
cp template.env.example template.env && $EDITOR template.env
./install.sh              # render only — review ./rendered/
./install.sh --apply      # install with automatic backups
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
