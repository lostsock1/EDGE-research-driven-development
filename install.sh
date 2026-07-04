#!/usr/bin/env bash
# install.sh — render the EDGE template with your values and (optionally)
# install the results into place.
#
#   ./install.sh            render only  -> ./rendered/   (safe, idempotent)
#   ./install.sh --apply    render, then copy into live locations with backups
#
# Rendering: every RDD_FOO=bar in template.env replaces the {{FOO}} token in
# the markdown/json5 templates. scripts/ is copied verbatim (it reads the same
# config at runtime instead). The two openclaw/*.json5 snippets are NEVER
# auto-merged into openclaw.json — that's a manual, reviewed step.

set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=template.env
if [ ! -f "$ENV_FILE" ]; then
  echo "install: $ENV_FILE not found. Start with:"
  echo "  cp template.env.example template.env   # then edit it"
  exit 2
fi

# shellcheck disable=SC1090
. "./$ENV_FILE"
if [ -z "${RDD_HOME:-}" ] || [ "${RDD_HOME}" = "/home/youruser" ]; then
  echo "install: RDD_HOME in template.env is unset or still the placeholder — edit template.env first." >&2
  exit 2
fi

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

rm -rf rendered
mkdir -p rendered

python3 - "$ENV_FILE" <<'PY'
import os, re, sys, pathlib

env_file = sys.argv[1]
tokens = {}
for line in open(env_file):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    k, v = k.strip(), v.strip().strip('"').strip("'")
    if k.startswith("RDD_"):
        tokens[k[4:]] = v

render_dirs = ["opencode", "openclaw", "workspace-edge", "project-repo"]
token_re = re.compile(r"\{\{([A-Z0-9_]+)\}\}")
missing = set()

for d in render_dirs:
    for src in pathlib.Path(d).rglob("*"):
        if not src.is_file():
            continue
        dst = pathlib.Path("rendered") / src
        dst.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text()

        def sub(m):
            key = m.group(1)
            if key in tokens:
                return tokens[key]
            missing.add(f"{src}: {{{{{key}}}}}")
            return m.group(0)

        dst.write_text(token_re.sub(sub, text))

if missing:
    print("WARNING — unresolved tokens (add the RDD_ variable to template.env):")
    for m in sorted(missing):
        print("  " + m)
else:
    print("Rendered with no unresolved tokens.")
PY

echo "Rendered tree: ./rendered/"

backup() { # backup <path> — timestamped copy next to the backups dir
  local f="$1"
  [ -f "$f" ] || return 0
  local bdir="$HOME/.config/edge-rdd/backups"
  mkdir -p "$bdir"
  cp "$f" "$bdir/$(basename "$f").$(date +%Y%m%d_%H%M%S)"
}

if [ "$APPLY" = 1 ]; then
  echo "--- applying ---"

  # 1. runtime config for the wrapper
  mkdir -p "$HOME/.config/edge-rdd"
  backup "$HOME/.config/edge-rdd/config.env"
  cp "$ENV_FILE" "$HOME/.config/edge-rdd/config.env"
  echo "installed: ~/.config/edge-rdd/config.env"

  # 2. dispatch wrapper (verbatim — reads config at runtime)
  mkdir -p "$RDD_HOME/.openclaw/shared-scripts"
  backup "$RDD_HOME/.openclaw/shared-scripts/edge-coder-run.sh"
  install -m 0755 scripts/edge-coder-run.sh "$RDD_HOME/.openclaw/shared-scripts/edge-coder-run.sh"
  echo "installed: $RDD_HOME/.openclaw/shared-scripts/edge-coder-run.sh"

  # 3. opencode agents
  mkdir -p "$RDD_HOME/.config/opencode/agents/code-monkeys"
  for f in rendered/opencode/agents/code-monkeys/*; do
    backup "$RDD_HOME/.config/opencode/agents/code-monkeys/$(basename "$f")"
    cp "$f" "$RDD_HOME/.config/opencode/agents/code-monkeys/"
  done
  echo "installed: opencode agents -> ~/.config/opencode/agents/code-monkeys/"

  # 4. research-agent workspace files
  WS="$RDD_HOME/.openclaw/workspace-${RDD_AGENT_ID}"
  mkdir -p "$WS/projects/${RDD_PROJECT_SLUG}"
  backup "$WS/USER.md"
  cp rendered/workspace-edge/USER.md "$WS/USER.md"
  for wf in PROJECT.md RESUME.md; do
    if [ ! -f "$WS/projects/${RDD_PROJECT_SLUG}/$wf" ]; then
      cp "rendered/workspace-edge/$wf" "$WS/projects/${RDD_PROJECT_SLUG}/$wf"
      echo "installed: $wf -> $WS/projects/${RDD_PROJECT_SLUG}/$wf"
    else
      echo "kept existing: $WS/projects/${RDD_PROJECT_SLUG}/$wf (diff against rendered/ manually)"
    fi
  done
  mkdir -p "$WS/projects/${RDD_PROJECT_SLUG}/notes"

  # 4c. Superior Architecture — the north-star research-track doc. Created once
  # per project, then maintained by the research agent. Never overwrite a live one.
  SA="$WS/projects/${RDD_PROJECT_SLUG}/notes/SUPERIOR_ARCHITECTURE.md"
  if [ ! -f "$SA" ]; then
    cp rendered/workspace-edge/SUPERIOR_ARCHITECTURE.md "$SA"
    echo "installed: SUPERIOR_ARCHITECTURE.md -> $SA"
  else
    echo "kept existing: $SA (diff against rendered/ manually)"
  fi

  # 4b. persona library + SOUL.md (the agent's operating philosophy).
  # SOUL.md is the OpenClaw-loaded bootstrap file; PERSONA.md is a non-loaded
  # marker — see workspace-edge/personas/README.md. Never overwrite a live SOUL.md.
  mkdir -p "$WS/personas"
  cp rendered/workspace-edge/personas/* "$WS/personas/"
  PERSONA="${RDD_PERSONA:-FRONTIER}"
  if [ ! -f "$WS/SOUL.md" ]; then
    if [ -f "$WS/personas/${PERSONA}.md" ]; then
      cp "$WS/personas/${PERSONA}.md" "$WS/SOUL.md"
      echo "installed: persona ${PERSONA} -> $WS/SOUL.md"
    else
      echo "WARNING: persona ${PERSONA} not found in $WS/personas/ — SOUL.md not seeded"
    fi
  else
    echo "kept existing: $WS/SOUL.md (swap manually: cp $WS/personas/${PERSONA}.md $WS/SOUL.md)"
  fi

  # 5. project-repo handoff docs — only fill gaps, never overwrite live docs
  if [ -d "${RDD_REPO_DIR:-/nonexistent}/.git" ]; then
    mkdir -p "$RDD_REPO_DIR/$RDD_DOCS_DIR"
    for f in rendered/project-repo/docs/agent/*; do
      t="$RDD_REPO_DIR/$RDD_DOCS_DIR/$(basename "$f")"
      if [ -f "$t" ]; then echo "kept existing: $t"; else cp "$f" "$t"; echo "seeded: $t"; fi
    done
  else
    echo "SKIPPED repo docs: RDD_REPO_DIR ($RDD_REPO_DIR) is not a git repo — seed them after cloning."
  fi

  echo ""
  echo "=== MANUAL STEPS REMAINING (never automated) ==="
  echo "1. Merge rendered/openclaw/agent.edge.json5 into agents.list[] in ~/.openclaw/openclaw.json"
  echo "2. Merge rendered/openclaw/topic.project-thread.json5 into your Telegram group's topics map"
  echo "3. openclaw config validate && systemctl --user restart openclaw-gateway"
  echo "4. Copy project-repo/.github/workflows/ci.yml.example into your repo as .github/workflows/ci.yml and adapt"
  echo "5. bash github/protect-branch.sh   (after CI ran once so the check contexts exist)"
  echo "6. Smoke test: bash $RDD_HOME/.openclaw/shared-scripts/edge-coder-run.sh status"
  echo "7. Kick off the thread: bash scripts/kickoff.sh (preflights the GitHub connection,"
  echo "   then posts the development-kickoff + pinnable command-palette messages)"
  echo "See docs/SETUP.md for the full walkthrough."
fi
