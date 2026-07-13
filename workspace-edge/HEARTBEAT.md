# Heartbeat — {{AGENT_NAME}}

## Superior Architecture integrity check

On a scheduled heartbeat/cron pass, run this for each directory under `projects/`:

```bash
python3 scripts/validate-superior-architecture.py \
  --workspace . --project <slug> --heartbeat
```

- `PASS` means the artifact is substantive, sourced, versioned, and fresh.
- `BLOCKED` is an operator-visible blocker, not permission to invent a product
  definition, sources, or architecture.
- `MODEL_ACTION` appears only when the authoritative `<slug>-north-star.md`
  exists and is substantive. A model must read that spec and the cited project
  evidence and author the synthesis; the validator never generates prose.

PR gate sweeps remain on-demand via `/gate sweep` and automatically follow a
CI-green dispatch. See `docs/OPERATIONS.md` §The PR gate.
