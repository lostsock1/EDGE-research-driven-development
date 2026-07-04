# {{PROJECT_NAME}} Resume State

Last updated: YYYY-MM-DD HH:MM — <one-line reason for the update>

## Purpose

This is the **first-read resume packet** for the {{PROJECT_NAME}} project thread (group `{{TG_TARGET}}`, topic `{{TG_THREAD}}`, agent `{{AGENT_ID}}`). Chat/session history can reset, compact, or restart; this file cannot. When the thread wakes up, resumes after a gap, or is asked "current status?", read this file BEFORE relying on memory or prior chat context.

## Canonical resume order

1. This file.
2. The project charter: `projects/{{PROJECT_SLUG}}/PROJECT.md`.
3. If implementation state matters: the repo's `{{DOCS_DIR}}/PROJECT_STATE.md` and `TASKS.md` on `{{MAIN_BRANCH}}`.
4. Newest notes under `projects/{{PROJECT_SLUG}}/notes/`.
5. For design/architecture questions: the north star, `projects/{{PROJECT_SLUG}}/notes/SUPERIOR_ARCHITECTURE.md`.

## Current project snapshot

- Status: <bootstrapping | researching | implementing M<N> | blocked on X>
- Primary repo: {{REPO_URL}} (branch `{{MAIN_BRANCH}}`, local clone `{{REPO_DIR}}`)
- Open PRs: <none | #N awaiting merge | #N red on <check>>
- Active work order: <TASKS.md id + one line, or none>
- Last dispatch: <run-id, model, outcome — or none>

## Latest known implementation state

<!-- What is true on the trunk right now, dated. -->

## Latest research artifacts

<!-- Newest staged/promoted findings, watchlist movements. -->

## Active blockers

<!-- Open EDGE requests, red CI, external waits — with ids/links. -->

## Next actions

1. <smallest next step, owner (operator / EDGE / coder)>

## Update protocol

Update this file in the same turn whenever any of these changed: project definition, coding progress, an active blocker, an accepted/rejected transfer, next actions, or dispatch status. Keep it short and operational — detailed evidence belongs in notes, not here.
