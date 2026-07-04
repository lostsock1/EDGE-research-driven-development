# EDGE Collaboration Protocol

This file is the durable two-way channel between the research agent (EDGE) and the coding agents (code-monkeys). Both runtimes read it; git tracks it.

## Responsibilities

### EDGE owns

- research, source discovery, method/frontier comparison, hypotheses
- contained lab experiments outside the production repo
- architecture / stack / model decisions and ADRs
- distilled recommendations, promoted via `RESEARCH_TRANSFER.md`
- the living **Superior Architecture** north-star doc (maintained outside the repo); reality-feedback logged here is folded back into it so the best-known design and the shipped code stay honest with each other

### Coding agents own

- reading the active execution docs and implementing against the real codebase
- tests, quality gates, git, and GitHub
- reality feedback when research proposals meet the real code
- updating canonical repo docs after a change lands

## When coding agents should ask EDGE for research

Architecture doesn't fit the existing seams · a dependency API differs from its docs · a bug looks upstream/platform · a method choice needs cross-source/paper/benchmark comparison · a gate fails and the fix implies a different architectural approach · a security question needs threat-model review · the task implies a stack/model/runtime swap or a new default · multiple plausible approaches and the deciding evidence is external.

Do NOT ask when local code inspection answers it, when it's straightforward implementation of an accepted ADR, or when a finding wouldn't change implementation, gates, contracts, or decisions.

## Research task format for EDGE

```md
### EDGE Research Task — <short title>

**Requester:** <agent/session>
**Date:** YYYY-MM-DD
**Priority:** blocking | high | normal | background

**Implementation context:**
- Current task:
- Files/components involved:
- Current behavior or failing test:
- Relevant active doc/ADR/task:

**Question for EDGE:**
One precise question.

**Constraints:**
- accepted stack / current baselines / hard requirements
- what cannot change without ADR approval

**Evidence needed:**
- official docs or source code / upstream issue / paper / lab experiment / comparison table

**Decision needed by coding agent:**
What the implementer needs to decide after EDGE responds.

**Expected output:**
- recommended approach, rejected alternatives, implementation impact,
  tests/gates to add, docs/ADRs to update, stop/replan triggers
```

## Implementation feedback format for EDGE

Use this when a coding agent tests an EDGE proposal against the real codebase. This is the main anti-hallucination loop.

```md
### EDGE Proposal Reality Feedback — <short title>

**Reporter:** <agent/session>
**Date:** YYYY-MM-DD
**Related EDGE proposal / transfer:** <path, note, or summary>
**Implementation task:** <TASKS.md item or issue>

**What EDGE proposed:**
**What the codebase actually allowed:**
- existing seam that worked / missing seam / conflicting test /
  runtime limitation / dependency mismatch

**Evidence:** file paths, failing test names, error output, doc conflicts

**Outcome:** works as proposed | works with modification | rejected | needs more research | docs stale

**Implementation change made or recommended:**
**Feedback for EDGE knowledge base:**
What EDGE should remember so it does not repeat the bad assumption.

**Repo doc updates needed:** <list or none>
```

## Envelope (wrap every entry below)

```
### <research-request | reality-feedback> — <short title>
ID: CM-YYYYMMDD-NN          # CM- = originated by code-monkeys
Re: <EDGE/CM id this answers, or —>
Status: open | acked | answered | promoted | implementing | implemented | closed
Priority: blocking | high | normal | background
Date: YYYY-MM-DD
<body = the matching template above>
```

## Open EDGE requests

> **Loop automation:** entries here with `Status: open` + `Priority: blocking|high` are auto-detected by the dispatch wrapper (`edge-coder-run.sh`) after each coder run, which nudges the project thread so EDGE/operator sees the handoff without polling. The coder does **not** send the nudge itself; it files the request here and sets `EDGE-REQUEST:` in its `=== LOOP STATUS ===` trailer. Close the entry once EDGE has answered and promoted it.

None.

## Implementation feedback log

None.

## Promotion rules

EDGE responses do not become coding instructions automatically. A response becomes active implementation guidance only when it is reflected in `RESEARCH_TRANSFER.md`, `TASKS.md`, `QUALITY_GATES.md`, an ADR, or `PROJECT_STATE.md`.

If an EDGE recommendation conflicts with active docs, coding agents stop and request a doc/ADR reconciliation before coding.

## Feedback quality bar

Reality feedback must be specific. Bad feedback says "EDGE was wrong." Good feedback names: which assumption failed, where the code contradicted it, what test/eval/runtime behavior proved it, what smaller or safer approach works instead, and what EDGE should remember.
