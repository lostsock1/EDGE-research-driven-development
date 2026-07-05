---
name: gate
description: "EDGE PR gate — run the GitHub sweep, list/approve pending merges & branch cleanups. Usage: /gate [sweep|pending|status|act <id>]"
user-invocable: true
---

# EDGE PR Gate Skill

**You MUST execute the command below and relay its output. Do NOT answer from memory or act on GitHub yourself.**

Take the user's argument after `/gate` (everything following the command). If it is empty, use `sweep`. Then run exactly:

```
bash {{HOME}}/.openclaw/shared-scripts/edge-pr-gate.sh <arg>
```

Sub-commands:
- (empty) or `sweep` — check every project's GitHub state (open PRs, CI verdicts, branch hygiene) and post approval messages — each with a what/consequence/why brief and inline buttons — to the gate thread. The script sends those itself; do not re-post or reformat them. Report the plain-language summary (per-project one-liners, or that everything is clean / `ALL_CLEAN`).
- `pending` — list open pending actions with their `eg:<id>` handles.
- `status` — pending actions plus the last few executed/failed ones.
- `act <id>` — execute ONE already-approved action (a merge, a branch prune, or a "do all" batch). The script re-verifies before acting. Only run this when the operator has explicitly approved that id (a button tap arrives as a message that is exactly `eg:<id>`; a 👍/✅ reaction or a plain "approve" resolves via `pending`).

Rules:
- Merges and branch deletions happen ONLY through `act` after the operator's explicit approval. NEVER run `gh pr merge` or delete branches directly, and never approve on the operator's behalf.
- Relay the script's stdout faithfully — the `DONE`/`FAILED`/`REFUSED` lines, `ALL_CLEAN`, and any pending list — in plain language.
