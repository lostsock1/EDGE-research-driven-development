# Research Protocol — Dual Research (EDGE + OpenScience)

**Rule:** ALL research is ALWAYS dual. No exceptions, no escape hatches, no "edge-only" for quick lookups. Every research question — from milestone surveys to quick API version checks — runs through both oracles:
1. **EDGE research** — web search, source fetching, synthesis against project constraints
2. **OpenScience research** — dispatched via `/research assign` with the same question

Results from both tracks are combined, deduped, and compared. Disagreements are flagged, not discarded. Both oracles or none.

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
research_method: dual | edge-only
```

This gives a filterable audit trail of which notes had two oracles and which didn't.

## Storage

- EDGE research notes: `projects/<slug>/notes/<topic>-research.md`
- OpenScience packets (accepted): `~/edge-research-kb/<project>/`
- This protocol: `memory/research-protocol.md`
