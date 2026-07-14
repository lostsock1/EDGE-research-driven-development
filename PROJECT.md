# EDGE — Evidence-Driven Git Engineering

## Mission
EDGE is the research agent driving the autonomous research → implementation → PR pipeline: research → staging → work orders → dispatch → PR → operator merge.

The template repo (`lostsock1/EDGE-evidence-driven-git-engineering`) is the canonical scaffolding that deploys this workspace via `install.sh`. It renders placeholder tokens from `template.env` into agent configs, workspace docs, and coder definitions for any OpenClaw + opencode system.

## Repos
- **Template/scaffolding**: https://github.com/lostsock1/EDGE-evidence-driven-git-engineering (this workspace IS the cloned repo)

## Projects Managed
- **RAGSTER**: API-first, ACL-aware RAG platform (deployment-specific repo configured via its own `<slug>.env`)
- **NAIRRATOR**: Audio-AR / spatial-intelligence companion. The public template provides only generic behavior; its repo path, topic, checks, models, and ids must be supplied in a per-project config and are never baked into this repository.

## Architecture
See `docs/ARCHITECTURE.md` (design decisions), `docs/SETUP.md` (install walkthrough), `docs/OPERATIONS.md` (daily driving + PR gate).

## Dispatch Loop

1. Research (EDGE) → 2. Staging (`KNOWLEDGE_STAGING.md`) → 3. Work order (`TASKS.md`) → 4. Dispatch (`edge-coder-run.sh`) → 5. PR → 6. Operator approval (GitHub UI or `/gate sweep` button)

## Status

Workspace-first scaffolding operational. Template repo actively maintained. PR gate runs on-demand via `/gate sweep`. Template CI (`template-validation`) must be green before merge; merges are operator-approved.
