# Persona Library

Swappable operating philosophies for the research agent. Each persona is a complete epistemic stance — how the agent generates ideas, evaluates evidence, runs experiments, and holds its own conclusions. **FRONTIER is the default**: `install.sh` copies it to the workspace `SOUL.md` on first install.

## How activation actually works

OpenClaw auto-loads a fixed set of bootstrap files from the agent workspace every session — **`SOUL.md` is one of them; `PERSONA.md` is NOT.** The only reliable way to make a persona the agent's default operating philosophy is to copy it over `SOUL.md`:

```bash
cp personas/AGAINST.md SOUL.md      # in the agent workspace root
```

> **Trap:** dropping a `PERSONA.md` in the workspace does nothing by itself — it is
> just a marker file the runtime never injects. If a persona swap "didn't take,"
> check that `SOUL.md` actually changed (`md5sum SOUL.md personas/<NAME>.md`).

### Per-topic override (persona for one thread only)

Paste the persona content into that topic's `systemPrompt` in `openclaw.json` (topic system prompts stack on top of the workspace bootstrap files), or — if you trust the agent to fetch it — reference it: `Load persona: AGAINST from personas/AGAINST.md and adopt it for this session.`

## Available personas

| File | Name | Philosophy | Best for |
|------|------|------------|----------|
| `FRONTIER.md` **(default)** | Recombinant Synthesis & Missing-Link Engine | Feyerabend × Deutsch: mechanism absorption, recombination, gap hunting, disciplined lab refutation, named LLM failure modes | Frontier research, synthesis, cross-domain recombination — the persona the EDGE-RDD loop was built around |
| `AGAINST.md` | Epistemological Anarchist | Feyerabend's *Against Method* — anything goes, counterinduction, proliferation | Paradigm-challenging inquiry, breaking methodological ruts |
| `INFINITY.md` | Progressive Truthseeker | Deutsch's *The Beginning of Infinity* — fallibilism, good explanations, conjecture-and-criticism | Rigorous epistemology, killing bad explanations |
| `BAYESIAN.md` | Probabilistic Reasoner | Jaynes' probability as extended logic — Bayes, MaxEnt, inference-before-decision | Quantitative reasoning under uncertainty, calibrated updating |

## Why the persona matters to this pipeline

The operating loop (work orders, frozen decision rules, negative results recorded, reality feedback) assumes a research agent that *wants* to refute its own ideas. FRONTIER's experiment-design protocol (pre-registered hypothesis / rival / discrimination / refutation condition) is the persona-level counterpart of the repo's `QUALITY_GATES.md` frozen-rule discipline — swap personas and you change how aggressively the research side self-criticizes, but the mechanical gates (branch protection, CI, reviewer, human merge) hold regardless.

## Creating new personas

1. Add `<NAME>.md` here (uppercase filename).
2. Include: **core axiom** (one sentence) · **operating principles** (actionable) · **guardrails** (what the axiom does not license) · **disposition** (tone/posture). FRONTIER additionally names the LLM failure modes it guards against — recommended.
3. Add a row to the table above; activate by copying over `SOUL.md`.
