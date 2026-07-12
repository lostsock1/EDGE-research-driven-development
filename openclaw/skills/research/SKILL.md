---
name: research
description: "OpenScience research dispatch — send a research question to the sandboxed research-only OpenScience workbench, list/show packets, accept/reject results. Usage: /research [assign \"<q>\" [--profile software]|list|status|show <id>|accept <id>|reject <id>|followup <id> \"<q>\" [--profile software]]"
user-invocable: true
---

# OpenScience Research Skill

**You MUST execute the command below and relay its output. Do NOT research the question yourself and do NOT answer from memory — OpenScience does the research.**

Take the operator's argument after `/research` (everything following the command). If it is empty, pass no argument (the script prints usage). Then run exactly:

```
bash {{HOME}}/.openclaw/shared-scripts/openscience-research.sh <arg>
```

Sub-commands:
- Default profile: `software` — optimized for software-development research: official docs, changelogs, source repos, standards, security advisories, maintainer issues/PRs, version constraints, implementation impact, validation tests, rollback/feature-flag guidance.
- `assign "<question>" [--project P] [--profile software] [--context "<text>"]` — dispatch a research question to the local, sandboxed, **research-only** OpenScience workbench. Returns `DISPATCHED <ERA-id>` **immediately**; the finished packet posts back to this thread with **Accept / Reject** buttons when ready (usually a minute or two). Do NOT wait, poll, or re-dispatch.
- `list` — assignments, produced packets, and pending approvals.
- `status` — OpenScience health + packet counts.
- `show <OSR-id>` — print a produced packet.
- `accept <OSR-id|handle>` — promote a packet into the research knowledge base (`~/edge-research-kb`). Single-use. Only when the operator approves — a button tap usually arrives as `/research accept <handle>`; full `OSR-...` ids also work.
- `reject <OSR-id|handle>` — archive a packet without adding it to the KB. Single-use. A button tap usually arrives as `/research reject <handle>`; full `OSR-...` ids also work.
- `followup <OSR-id|handle> "<question>" [--profile software]` — dispatch a follow-up question referencing a prior packet.

Rules:
- OpenScience is **research + knowledge-base ONLY**. It never writes code, opens PRs, dispatches coders (opencode), deploys, or messages anyone — never ask it to.
- **Accepting a packet stores knowledge; it does NOT implement anything.** Promoting a finding into an implementation work order is a separate, explicit {{AGENT_NAME}} step (`edge-coder-run.sh` + the PR gate) that you take only when the operator asks.
- Relay the script's stdout faithfully (the `DISPATCHED` / `accepted` / `rejected` / list / status lines) in plain language. Never accept or reject on the operator's behalf.
