📌 {{AGENT_NAME}} COMMAND PALETTE (pin me) — short commands, defined in PROJECT.md §Operating loop

▶️ DAILY DRIVERS
• status — resume-order read → active task, open PRs, CI, blockers, next action
• go — dispatch the last posted work order (completion + CI verdict arrive here)
• next — top TASKS.md item → loop steps 1–3 → work order → waits for go
• work order for <thing> — frame any idea: ID + acceptance criteria + frozen rule → waits for go

🔬 RESEARCH
• research <topic/link> — mine for mechanisms, stage in KNOWLEDGE_STAGING, flag impl-changing finds
• promote — staged findings → RESEARCH_TRANSFER → TASKS/ADR
• watchlist — review/refresh the research watchlist, report movement

🚢 SHIP & REPO
• sweep — open PRs, stale branches, failed workflows, TASKS drift → one status post
• /gate (or gate sweep) — PR gate now: green PRs + stale branches → approval buttons in the gate thread (auto every 6h)
• /gate pending — list open gate asks (tap a button, react 👍, say "approve", or use "☑️ Do all N" to clear a project)
• fix the red PR — work order referencing the failing check → go-gate → dispatch
• merged — post-merge closeout: TASKS checkboxes, RESUME.md, EDGE_COLLABORATION answers
• docs true? — verify PROJECT_STATE/TASKS/README against {{MAIN_BRANCH}}; drift becomes a work order

🛠 WHEN SOMETHING IS OFF
• dispatch status — wrapper status: lock holder, recent runs, ledger
• what happened — read last run log + CI, explain the failure plainly
• re-read PROJECT.md — re-sync a live session after any rule change

Flow: next → go → (auto: DISPATCHED → completion + PR → CI verdict) → you approve the merge (GitHub UI, or one tap on the gate's ✅ button) → merged.
