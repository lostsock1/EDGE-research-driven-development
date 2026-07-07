# EDGE Gapped Lab

Ephemeral Docker containers for contained, reversible experiments. The lab is the **discipline** — every run is pre-registered, resource-bounded, isolated, and auto-destroyed. The container is just the mechanism.

## Quick start

```bash
# Build the lab image (once)
lab/lab-run.sh --image

# Create a new experiment
lab/lab-run.sh --new my-test

# Fill in protocol.yaml and run.sh, then run it
lab/lab-run.sh lab/experiments/my-test

# List past experiments
lab/lab-run.sh --list
```

## Experiment lifecycle

1. **Pre-register** — protocol.yaml with hypothesis, rival, discrimination, metric, refutation_condition (required; the lab refuses to run without them)
2. **Write** — run.sh or run.py with your experiment
3. **Run** — `lab-run.sh <dir>` launches a fresh container, captures output, auto-destroys
4. **Record** — results.txt, container.log, and output/ are saved to the experiment directory
5. **Promote or discard** — findings that survive go into project notes; the experiment dir is the audit trail

## Container environment

- **Python 3.12** with numpy, pandas, scipy, scikit-learn, matplotlib, pytest, duckdb, pyarrow, httpx, pydantic, rich
- **System tools**: git, curl, jq, yq, sqlite3, graphviz
- **Network**: `none` by default (air-gapped). Set `LAB_NETWORK=bridge` if needed
- **Memory/CPU**: bounded per run (default 2g/2 CPUs)
- **Timeout**: hard wall clock limit (default 600s)
- **Mounts**: experiment dir at `/lab/experiment/` (rw), workspace projects at `/lab/workspace/projects/` (ro)

## Protocol requirements

Every experiment must pre-register these fields (from the SOUL.md protocol):

| Field | Meaning |
|---|---|
| `hypothesis` | The explanation under test |
| `rival` | The incompatible alternative |
| `discrimination` | How they predict differently |
| `metric` | What you measure |
| `refutation_condition` | The result that kills the hypothesis |

Use `lab/protocol.sh --new <slug>` for interactive creation, or `lab/protocol.sh --template` for a blank template.

## Configuration

Copy `lab/lab.env.example` to `lab/lab.env.local` and edit. Or export vars:

```bash
export LAB_MEMORY=4g
export LAB_TIMEOUT=1200
export LAB_NETWORK=bridge
lab/lab-run.sh lab/experiments/my-test
```

## Architecture

The gapped lab is one of three experiment layers in EDGE:

1. **Gapped lab** (this) — EDGE designs the test, Docker enforces containment
2. **Implementation oracle** — coder dispatch tests research against real code
3. **OpenScience** — external research sandbox (read-only, no code execution)

See `docs/ARCHITECTURE.md` for the full loop.
