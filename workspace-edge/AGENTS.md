# {{AGENT_NAME}} Workspace Guide

{{AGENT_NAME}} (Evidence-Driven Git Engineering) is the overarching research agent.

## Persona system
- {{AGENT_NAME}} can adopt different operating philosophies via the persona library at `personas/`.
- **Activation mechanism:** copy the chosen persona over `SOUL.md` (`cp personas/<X>.md SOUL.md`). `SOUL.md` is the file OpenClaw actually bootstraps into context; `PERSONA.md` at workspace root is only a marker copy of the active persona and is NOT loaded at runtime (the `bootstrap-extra-files` hook has no paths configured).
- When swapping personas, update both files: `SOUL.md` (the live one) and `PERSONA.md` (the marker), so they stay identical.
- A persona can also be reinforced per-topic via `systemPrompt` overlay in `openclaw.json`.
- Current active persona: {{PERSONA}} (see `PERSONA.md` marker).

## Operating model
- {{AGENT_NAME}} owns cross-project research standards, source discipline, and reusable methods.
- Each chat topic routed to {{AGENT_NAME}} is a separate project thread with its own session history.
- Project-specific rules live under `projects/<project>/PROJECT.md` and may be reinforced by chat topic `systemPrompt` overlays.

## Current projects
<!-- EDIT: list active projects here. Delete this comment after populating. -->
- `projects/{{PROJECT_SLUG}}/` — ...

## Project kickoff: north-star track
- New projects start with an operator **north-star specification**, generated via `templates/north-star-spec.md` (full prompt, short variant, and technical/product/adversarial add-ons — usage header in the template).
- The spec lands verbatim at `projects/<project>/notes/<project>-north-star.md` (`status: unprocessed`); {{AGENT_NAME}} distills it into the charter Mission, then synthesizes `notes/SUPERIOR_ARCHITECTURE.md` from it.
- Raw spec sections are never work orders. Promotion into a repo is gated through `KNOWLEDGE_STAGING.md` → `RESEARCH_TRANSFER.md` → `TASKS.md`; the spec and the north-star doc themselves never enter the repo.

## Repo scaffolding
- The repo-scaffold template lives in the {{AGENT_NAME}} repo: `lostsock1/EDGE-evidence-driven-git-engineering` → `project-repo/` (`.github/workflows/ci.yml.example` + `docs/agent/` handoff docs). Seeded into each project repo by `install.sh`; **not** stored per-project in this workspace.
- Per-repo handoff docs (`PROJECT_STATE`, `TASKS`, `QUALITY_GATES`, `KNOWLEDGE_STAGING`, `RESEARCH_TRANSFER`, `EDGE_COLLABORATION`) live **inside each project's git repo** under `docs/agent/`, not under `projects/<name>/`.
- Do **not** keep per-project `repo-seed/` staging copies in the workspace.

## Install & portability
- This workspace is a **rendered {{AGENT_NAME}} install** plus a local Obsidian layer. `install.sh` (from `lostsock1/EDGE-evidence-driven-git-engineering`) renders the `template.env` values into the double-brace tokens and applies; it is fully portable (no hardcoded paths in the templates).
- **install.sh owns** (re-render/re-apply on a new system): shared `~/.config/edge-rdd/config.env`, per-project `~/.config/edge-rdd/<slug>.env`, and `{gate,research}.env`, `shared-scripts/edge-coder-run.sh` + `edge-pr-gate.sh` + `openscience-research.{sh,py}` + `openscience-smoke.sh`, the `gate`/`research` skills, opencode `code-monkeys/` agents, `USER.md`, `personas/`, `projects/<slug>/{PROJECT,RESUME}.md` + seeded `notes/`, and each repo's `docs/agent/`.
- **Local layer (NOT from install.sh — version-control separately)**: the numbered Obsidian vault (`00_INBOX`–`99_ARCHIVE`), `.obsidian/`, `EDGE Vault.md`, `SKILL-REGISTRY.md`, other root docs, multi-project configs, and per-project `notes/` beyond the seeded files.
- **Runtime state (never port)**: `.openclaw/`, `storage/`, `snapshots/`, logs, `.qdrant-initialized`.
- **Rebuild on a new system:** clone {{AGENT_NAME}} → `cp template.env.example template.env` → fill in → `./install.sh` (review `rendered/`) → `./install.sh --apply` → merge `rendered/openclaw/*.json5` into `openclaw.json` → `scripts/kickoff.sh`. Re-render `config.env`; do not copy it.

## Durable outputs
- Store durable research notes under the matching project directory.
- Use `projects/<project>/notes/` for working notes and watchlists.

## Private web access
- {{AGENT_NAME}} may use the browser tool for operator-approved private research sessions.
- Do not write site passwords into notes, prompts, project manifests, generated skills, or reports.
- Prefer an authenticated browser session/cookie over plaintext credential storage. If login is needed, ask the operator to provide credentials through the active private channel or secret manager rather than persisting them in the workspace.

## Skill registry
- Global {{AGENT_NAME}} skill registry: `SKILL-REGISTRY.md`
- Per-project skill manifests live at `projects/<project>/SKILLS.md`

When creating book-derived skills with `book-to-skill`, update the registry first, then add the skill only to the relevant project topic allowlists.
