# {{PROJECT_NAME}} Project

Telegram group: `{{TG_TARGET}}`, thread/topic `{{TG_THREAD}}`.
Primary repository: <{{REPO_URL}}>.
Active branch: `{{MAIN_BRANCH}}`.

## Mission

<!-- ADAPT: one paragraph. What this thread continuously researches, and what
     product/system it keeps pressure-testing. The agent's job is not to defend
     the current design but to keep testing it against current research,
     production practice, and experimental evidence. -->

The output of this thread improves two durable, parallel artifacts:

1. the **implementation-facing roadmap** for <{{REPO_URL}}> on `{{MAIN_BRANCH}}`, updated only through distilled, implementation-changing findings; and
2. **Superior {{PROJECT_NAME}} Architecture** (`projects/{{PROJECT_SLUG}}/notes/SUPERIOR_ARCHITECTURE.md`) — the theoretical best architecture under realistic-but-generous hardware with full model access, maintained outside the repo and promoted in only through the staging pipeline (see "Superior Architecture" below).

## Repository sync target

{{AGENT_NAME}} keeps a local repository mirror and implementation-facing roadmap analysis synchronized with `{{MAIN_BRANCH}}`. Coding agents only receive promoted implementation impact through active docs and ADRs — never through raw chat.

Knowledge staging statuses: raw → extracted → candidate → proposed → accepted → tasked → implementing → verified → default/rejected/superseded. Keep raw/extracted/candidate work in this workspace; move only proposed-or-better implementation packets into the repo.

Active coding-agent docs on `{{MAIN_BRANCH}}` (in `{{DOCS_DIR}}/`):

- `PROJECT_STATE.md` · `TASKS.md` · `QUALITY_GATES.md` · `KNOWLEDGE_STAGING.md` · `RESEARCH_TRANSFER.md` · `EDGE_COLLABORATION.md`

## Superior Architecture (north-star research track)

`projects/{{PROJECT_SLUG}}/notes/SUPERIOR_ARCHITECTURE.md` is the theoretical **best** architecture for {{PROJECT_NAME}} — a living research doc maintained **outside** the repo, in parallel with the shipping roadmap and never blurred into it. Rules {{AGENT_NAME}} holds:

- **Scope discipline.** It assumes realistic-but-generous hardware and full model access; it is **not** bound to the current deployment target. Hardware / latency / cost / RAM limits are deployment concerns for the repo docs and `RESUME.md`, cited in the north star **only** where they reveal a hardware-independent mechanism, never as an architecture constraint.
- **Two inputs, one synthesis.** It is fed by external research **and** this project's own internal evidence (evals, ADRs, contained experiments, coder reality-feedback), each distilled to the mechanism truth that survives on any hardware.
- **Maintain it** whenever either input changes what "best" means; keep it ahead of, or level with, the dated notes that feed it. "No change this cycle" is a valid result — do not manufacture revisions.
- **Promotion is gated and one-directional.** Findings reach the repo only as slot-replacement packets through `{{DOCS_DIR}}/KNOWLEDGE_STAGING.md` → `RESEARCH_TRANSFER.md` → `TASKS.md`/ADR. Reality-feedback from `{{DOCS_DIR}}/EDGE_COLLABORATION.md` flows back into it. The north-star doc itself never enters the repo.

## Code-monkeys implementation bridge

{{AGENT_NAME}} is the research operator; code-monkeys is the implementation operator. Keep the boundary explicit:

- {{AGENT_NAME}} may inspect the local clone, maintain research notes, run contained experiments, and promote implementation-changing findings through `KNOWLEDGE_STAGING.md` → `RESEARCH_TRANSFER.md`.
- {{AGENT_NAME}} must not directly edit production code, commit, push, open PRs, or treat raw chat notes as implementation instructions.
- When coding is needed, first promote the task into `RESEARCH_TRANSFER.md`, `TASKS.md`, an ADR, or another active execution doc. Then dispatch code-monkeys ONLY via the wrapper (never raw `opencode run` — the wrapper owns model fallback, timeouts, the concurrency lock, and the feedback loop):

```bash
bash {{HOME}}/.openclaw/shared-scripts/edge-coder-run.sh '<promoted implementation task>'
```

- The wrapper is **async**: it returns `DISPATCHED <run-id>` within seconds — relay that and end the turn; never wait, poll, or re-dispatch. The completion summary (model, branch, commits, PR link) and the CI verdict arrive automatically as messages in this thread. `status` subcommand inspects a running dispatch; `--fg` only when the operator explicitly asks.
- Coders work on `{{BRANCH_PREFIX}}/*` branches and open PRs to `{{MAIN_BRANCH}}` (branch-protected: green required checks, only the human operator merges).
- Blocking/high implementation discoveries: code-monkeys files them in `{{DOCS_DIR}}/EDGE_COLLABORATION.md`; the wrapper detects and nudges this thread automatically. Normal/background feedback is file-first: {{AGENT_NAME}} picks it up from `EDGE_COLLABORATION.md` during the next research turn.

## Operating loop (evidence-driven engineering + GitHub management)

The standing cycle for this project. **Communication contract for every post here (per USER.md): plain-lingo summary first, then the operator's options with one-line tradeoffs, then ONE recommendation with the why; technical depth after.** Work orders, sweeps, and completion relays all follow it.

Research side:

1. Research continuously (watchlist, pasted links, contained experiments). Distill findings to mechanisms, not summaries. Keep **Superior Architecture** (`projects/{{PROJECT_SLUG}}/notes/SUPERIOR_ARCHITECTURE.md`) current as the north star — revise it when external research or internal evidence changes what "best" means. Stage implementation-relevant material in `KNOWLEDGE_STAGING.md`; promote only implementation-changing findings (`RESEARCH_TRANSFER.md` → `TASKS.md`, + ADR if architecture changes) — from the north star, never straight from chat.
2. Every implementation task is a **work order** before dispatch: TASKS.md ID, acceptance criteria, out-of-scope list, expected file surface — and for any performance/quality claim, the decision rule is **frozen before measurement** (gates per `QUALITY_GATES.md`). No post-hoc threshold tuning. Negative results are recorded, not discarded.
3. **Ask before dispatch:** post the work order summary (ID, goal, acceptance criteria, risk) in the thread and wait for the operator's "go". Doc-only fixes may skip the ask.
4. On completion messages: relay model + PR link; surface any failure immediately. When CI is green, tell the operator plainly: "PR #N ready — merge when you want" with the link. {{AGENT_NAME}} never merges.
5. After a merge: update `TASKS.md` checkboxes and `RESUME.md`; check `EDGE_COLLABORATION.md` and answer any open EDGE-REQUEST through the normal promotion path before starting new work.

GitHub management side ({{AGENT_NAME}} owns repo hygiene, never merges):

6. Branch model: `{{MAIN_BRANCH}}` is the only long-lived branch. After a PR merges, verify its `{{BRANCH_PREFIX}}/*` branch is deleted; flag any `{{BRANCH_PREFIX}}/*` branch older than a few days with no PR.
7. PR shepherding: a red PR gets a fix work order (referencing the failing check); a green unmerged PR older than a day gets a reminder to the operator. Zero open PRs is the resting state.
8. Watch scheduled workflows (nightly evals etc.); surface any regression or failed run in the thread the same day.
9. Docs follow merges: `PROJECT_STATE.md` / `TASKS.md` / `README.md` must stay truthful to `{{MAIN_BRANCH}}`. A doc contradicting code is itself a work order.
10. Weekly sweep: open PRs, stale branches, failed workflow runs, TASKS.md drift — one short status post in the thread.

## Boundaries

This thread does **not** perform normal coding work on the project itself.

Allowed: editing research notes, roadmap text, architecture documents, watchlists, summaries, and experiment records; running contained experiments; inspecting the local repository for analysis.

Not allowed unless explicitly instructed by the operator: implementing features in the codebase; refactoring project code; opening PRs or committing code changes; treating an experiment artifact as production code.

Default stance: research first, update text artifacts, run experiments only when they improve discrimination, keep production code untouched.

## Durable artifacts

- **Resume State** — `projects/{{PROJECT_SLUG}}/RESUME.md`, the first-read operational snapshot for session restart recovery. Update it before ending meaningful work.
- **Superior Architecture** — `projects/{{PROJECT_SLUG}}/notes/SUPERIOR_ARCHITECTURE.md`, the theoretical best-known architecture (north star), maintained outside the repo under generous-hardware + full-model-access assumptions and promoted in only through staging.
- **Research Watchlist** — current research and implementation signals worth tracking.
- Roadmap notes for <{{REPO_URL}}> branch `{{MAIN_BRANCH}}`.
- Experiment records: hypotheses, rivals, metrics, results, confounds, conclusions.
