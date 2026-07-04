# Knowledge Staging Pipeline

How knowledge developed by the research agent (EDGE) becomes clean, auditable, implementation-ready work in this repo.

Core rule: **raw research knowledge never enters the repo directly.** The repo receives only staged, distilled, implementation-changing knowledge packets with stable contracts, gates, and rollback paths.

## Pipeline overview

```text
EDGE raw discovery
  -> EDGE extraction
  -> EDGE candidate finding
  -> EDGE-developed proposal
  -> repo transfer staging (RESEARCH_TRANSFER.md)
  -> repo decision / ADR
  -> coding-agent task (TASKS.md)
  -> implementation + verification (PR + CI + reviewer)
  -> promoted default OR rejected feedback back to EDGE
```

## Status ladder

Use these statuses consistently across EDGE notes, `RESEARCH_TRANSFER.md`, `TASKS.md`, ADRs, and feedback logs:

| Status | Owner | Location | Meaning | Next transition |
|---|---|---|---|---|
| `raw` | EDGE | EDGE inbox/notes | Unprocessed source, link, paper, issue, or idea | `extracted` or dropped |
| `extracted` | EDGE | EDGE notes/watchlist | Claim/mechanism summarized with source and relevance | `candidate`, watchlist, or dropped |
| `candidate` | EDGE | EDGE notes/lab | Plausible improvement with slot, baseline, and evidence needs | `proposed` or watchlist |
| `proposed` | EDGE/planner | `RESEARCH_TRANSFER.md` | Repo-visible knowledge packet; not yet accepted | `accepted`, `rejected`, or `deferred` |
| `accepted` | Planner/operator | ADR / active docs | Decision exists; coding agents may task it | `tasked` |
| `tasked` | Planner/coder | `TASKS.md` | Broken into implementable steps with gates | `implementing` |
| `implementing` | Coding agent | code branch + tests | In progress, usually behind flag/profile/adapter | `verified` or feedback |
| `verified` | Reviewer/CI | test output, eval reports | Gates pass; promotion decision can be made | `default`, experimental, or rejected |
| `default` | Planner/operator | active docs + config | Candidate is now the default behavior | monitor/reopen on regression |
| `rejected` | EDGE/planner/reviewer | EDGE notes + transfer/ADR | Evidence or implementation reality rejected it | feed learning back to EDGE |
| `superseded` | EDGE/planner | EDGE notes + active docs | A newer proposal replaces it | follow the newer proposal |

## Rejection rules

Reject (or bounce back to EDGE) any packet that arrives without: a named slot/baseline · a stable contract statement · required gates · a rollback path · a stop/replan trigger. Negative results are **recorded** in the transfer record (Status: rejected + why), never silently discarded — they are how the knowledge base learns.

## Frozen decision rules

For any performance/quality claim, the decision rule (metric, threshold, dataset, pass/fail condition) is **frozen in the work order before measurement**. No post-hoc threshold tuning. If the frozen gate turns out to measure the wrong thing, that is itself a research finding: record it, amend the gate design through a new proposal, and re-measure — never quietly move the goalposts on live data.

## The north-star source (Superior Architecture)

`raw`/`extracted`/`candidate` work is synthesized in the research agent's living **Superior Architecture** doc — the theoretical best-known design, maintained *outside* this repo under realistic-but-generous-hardware, full-model-access assumptions. That doc is where external research and this project's own internal evidence (evals, ADRs, contained experiments, reality-feedback) are reconciled into hardware-independent mechanism truths. A mechanism becomes a `proposed` packet here only when it is ready to change an execution surface; **the north-star doc itself never enters the repo.** Rejections and implemented-and-proven outcomes are fed back into it, so the north star and the shipped code stay honest with each other.
