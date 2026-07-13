# Research Protocol — Dual Research (EDGE + OpenScience)

**Rule:** ALL research is ALWAYS dual. No exceptions, no escape hatches, no "edge-only" for quick lookups. Every research question — from milestone surveys to quick API version checks — runs through both oracles:
1. **EDGE research** — web search, source fetching, synthesis against project constraints
2. **OpenScience research** — dispatched via `/research assign` with the same question

Results from both tracks are combined, deduped, and compared. Disagreements are flagged, not discarded. Both oracles or none.

## Tooling

The OpenScience side of the protocol is shipped by this template: the
`/research` skill (`openclaw/skills/research/SKILL.md`), the dispatch scripts
(`scripts/openscience-research.sh` / `.py`, `scripts/openscience-smoke.sh`),
the generated `~/.config/edge-rdd/research.env`, and the hardened
`openscience/openscience.service` unit — setup in
[openscience/README.md](../openscience/README.md). Model choices are yours.

## Rationale

EDGE and OpenScience use different search providers, models, and methodologies. Independent convergence = stronger signal. Divergence = something worth investigating. This mirrors the persona's "proliferate rivals" principle — two independent research oracles are the evidence-gathering equivalent.

## Procedure

1. **Dispatch OpenScience FIRST** — it's async (posts back in 2-5 minutes). Dispatching first means both run in parallel.
2. **Do EDGE research while OpenScience runs** — web_search + web_fetch + synthesis against project constraints.
3. **Combine when both are in** — union of findings, flag disagreements, note which source found what.
4. **Write combined note** to `projects/<slug>/notes/<topic>-research.md` with a `## Cross-reference` section.
5. **If OpenScience recommends "create-edge-work-order"** — review for promotion through the staging ladder.

## Research is ALWAYS dual

There are NO exceptions. No "edge-only" escape hatches. No "skip for quick lookups." Every research question — from milestone architecture surveys to one-line API version checks — goes through both EDGE and OpenScience in parallel. Two oracles or none.

This is NOT optional. It is the default operating mode. A research note without `research_method: dual` and a completed OpenScience cross-reference is incomplete.

## Execution pattern

0. **Verify you're in the correct project thread.** If not, redirect. The research pipeline only works when it runs in the project's own thread.
1. **Dispatch OpenScience FIRST** — always. Before any EDGE web search. It's async (2-5 min).
2. **EDGE research in parallel** — web_search + web_fetch while OpenScience runs.
3. **For large EDGE research (>3 web searches):** spawn a sub-agent. Clean context, no LCM compaction.
4. **Accept OpenScience packet immediately** when it arrives — don't let it sit in candidate limbo.
5. **Combine and write note** with `research_method: dual` and `## Cross-reference` before closing the research session.

## Comparison format

Every dual-research note must end with a `## Cross-reference` section:

| Flag | Meaning |
|---|---|
| **Converged** | Both agree → high confidence |
| **Diverged** | Disagree on key finding → flag for deeper investigation |
| **Complementary** | Found different things, no conflict → union is richer |

## Research metadata

Every research note YAML frontmatter must include:

```yaml
research_method: dual
```

This gives a filterable audit trail; an incomplete single-oracle attempt is recorded as a blocker in prose, not mislabeled as completed research.

## Thread routing

**All per-project research MUST be dispatched from the project's own Telegram thread.** The cross-project hub thread is for coordination, triage, and PR gate approvals — NOT for per-project research.

| Project | Thread | Purpose |
|---|---|---|
| <project A> | its own topic | project research, staging, promotion, dispatch |
| <project B> | its own topic | project research, staging, promotion, dispatch |
| hub (home thread) | the gate/coordination topic | cross-project coordination, PR gate, protocol, triage |

**Rule:** If you are in the EDGE thread and someone asks for project-specific research, redirect them to the project thread. If you already did the research from the wrong thread, cross-post the findings immediately.

## Storage

- EDGE research notes: `projects/<slug>/notes/<topic>-research.md`
- OpenScience packets (accepted): `~/edge-research-kb/<project>/`
- This protocol: `memory/research-protocol.md`
