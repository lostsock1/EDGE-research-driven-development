# Research Protocol — Dual Research (EDGE + OpenScience)

**Rule:** Whenever research is needed for any EDGE project, it MUST be done in parallel:
1. **EDGE research** — web search, source fetching, synthesis against project constraints
2. **OpenScience research** — dispatched via `/research assign` with the same question

Results from both tracks are combined, deduped, and compared. Disagreements are flagged, not discarded.

## Rationale

EDGE and OpenScience use different search providers, models, and methodologies. Independent convergence = stronger signal. Divergence = something worth investigating. This mirrors the persona's "proliferate rivals" principle — two independent research oracles are the evidence-gathering equivalent.

## Procedure

1. **Dispatch OpenScience FIRST** — it's async (posts back in 2-5 minutes). Dispatching first means both run in parallel.
2. **Do EDGE research while OpenScience runs** — web_search + web_fetch + synthesis against project constraints.
3. **Combine when both are in** — union of findings, flag disagreements, note which source found what.
4. **Write combined note** to `projects/<slug>/notes/<topic>-research.md` with a `## Cross-reference` section.
5. **If OpenScience recommends "create-edge-work-order"** — review for promotion through the staging ladder.

## When to use dual research

**Use dual research for:** milestone research, ADR support, technology evaluation, architecture decisions, literature surveys. Rule of thumb: if the research would produce a `projects/<slug>/notes/` file, it's worth dual-tracking.

**Skip OpenScience for:** quick factual lookups (API version, syntax, "what does this config do"), single-source verification (reading one paper/spec), time-sensitive questions where 5 minutes matters.

## Large research: use sub-agents

For EDGE-side research that needs more than 2-3 web searches, spawn a sub-agent with the research question. Sub-agents get a fresh context window — no LCM compaction, clean tool outputs. OpenScience already runs in its own sandbox; EDGE should too when the topic warrants it.

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
