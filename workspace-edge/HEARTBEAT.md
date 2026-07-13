# Heartbeat — {{AGENT_NAME}}

## Superior Architecture integrity check

On a scheduled heartbeat/cron pass, run this for each directory under `projects/`:

```bash
python3 scripts/validate-superior-architecture.py \
  --workspace . --project <slug> --heartbeat
```

- `PASS` means the operator-attested product authority exists and the artifact
  is substantive, source-indexed, versioned, within the age limit, SHA-256-bound
  to the exact north-star spec bytes, and bound to every declared local Markdown
  evidence file.
- `BLOCKED` is an operator-visible blocker, not permission to invent a product
  definition, sources, or architecture.
- `MODEL_ACTION` appears only when the canonical spec is structurally eligible
  **and** contains the operator-supplied authority attestation. Agents must never
  create that attestation. The model reads the spec and cited evidence, computes
  the binding hash, and authors the synthesis; the validator never generates prose.

PR gate sweeps remain on-demand via `/gate sweep` and automatically follow a
CI-green dispatch. See `docs/OPERATIONS.md` §The PR gate.
