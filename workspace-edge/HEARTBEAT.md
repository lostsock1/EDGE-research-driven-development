# Heartbeat — {{AGENT_NAME}}

## RDD integrity sweep (architecture + research loop)

Every heartbeat, run exactly this and nothing else for the integrity check:

```bash
bash {{HOME}}/.openclaw/shared-scripts/rdd-heartbeat-sweep.sh
```

- If the last line is `NO_CHANGE`: reply `HEARTBEAT_OK`. Do not repeat known-blocked state.
- If the last line is `CHANGED`: summarize the `BLOCKED:` / `ATTENTION:` lines in plain
  language for the operator (what changed, what only the operator can unblock).
- `PASS` means the operator-attested product authority exists and the artifact
  is substantive, source-indexed, versioned, within the age limit, SHA-256-bound
  to the exact north-star spec bytes, and bound to every declared local Markdown
  evidence file.
- `BLOCKED` is an operator-visible blocker, not permission to invent a product
  definition, sources, or architecture. `AUTHORITY_REQUIRED` / attestation blockers
  are **operator-only**: never add `authority: operator-supplied` to a spec.
- `MODEL_ACTION` appears only when the canonical spec is structurally eligible
  **and** contains the operator-supplied authority attestation. It is your
  instruction to synthesize the named Superior Architecture from the attested spec
  plus evidence in that project's `notes/` (accepted research packets land there).
  Bind `north_star_sha256` and `local_source_sha256` to exact file bytes, then
  re-run the sweep to confirm; the validator never generates prose.

The sweep validates every workspace project (dirs under `projects/` with a
`PROJECT.md`; pin the list or non-default artifact paths via `RDD_SWEEP_PROJECTS`),
nags when research notes are newer than a project's last Superior Architecture
synthesis (evidence not yet folded in — fold it in and re-bind, or touch the
artifact after judging), flags stale research assignments (a dispatch that died
after `DISPATCHED`) and packets waiting >24h for operator Accept/Reject, and
checks OpenScience health.
Run log: `~/.local/state/edge-rdd/arch-sweep.log`.

PR gate sweeps remain on-demand via `/gate sweep` and automatically follow a
CI-green dispatch. See `docs/OPERATIONS.md` §The PR gate.
