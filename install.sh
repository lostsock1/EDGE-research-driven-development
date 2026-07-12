#!/usr/bin/env bash
# install.sh — workspace-first EDGE scaffolding.
#
#   ./install.sh            render only  -> ./rendered/   (safe, idempotent)
#   ./install.sh --apply    render, then install into ~/.openclaw/workspace-edge/
#
# Workspace-first: everything canonical lives inside ~/.openclaw/workspace-${RDD_AGENT_ID}/.
# System paths (~/.config/edge-rdd, ~/.openclaw/skills/gate, etc.) are symlinked
# to the workspace so the runtime finds them without special configuration.
#
# Structure after --apply:
#   ~/.openclaw/workspace-${AGENT_ID}/
#   ├── SOUL.md, AGENTS.md, HEARTBEAT.md, ...     (workspace docs)
#   ├── personas/                                  (FRONTIER, etc.)
#   ├── templates/                                 (north-star-spec.md, etc.)
#   ├── projects/<slug>/                           (git clone of project repo)
#   ├── context/<slug>/notes/                      (EDGE research context)
#   ├── config/edge-rdd/config.env                 (dispatch config — primary project + model chain)
#   ├── config/edge-rdd/gate.env                   (PR gate hub)
#   ├── config/edge-rdd/research.env               (OpenScience research dispatch)
#   ├── config/opencode/agents/code-monkeys/       (coder, reviewer, _shared)
#   ├── skills/gate/SKILL.md                       (/gate command)
#   ├── skills/research/SKILL.md                   (/research command)
#   └── scripts/edge-*.sh + openscience-*          (dispatch + research scripts)

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

# Validate required vars
for var in RDD_AGENT_ID RDD_AGENT_NAME RDD_PROJECT_NAME RDD_PROJECT_SLUG RDD_REPO_URL RDD_REPO_SLUG; do
  if [ -z "${!var:-}" ]; then
    echo "install: $var is required in template.env" >&2
    exit 2
  fi
done

# Derive paths
WORKSPACE="$HOME/.openclaw/workspace-${RDD_AGENT_ID}"
REPO_DIR="$WORKSPACE/projects/${RDD_PROJECT_SLUG}"
CONFIG_DIR="$WORKSPACE/config/edge-rdd"
STATE_DIR="$HOME/.local/state/edge-rdd"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# ---- RENDER ----------------------------------------------------------------
rm -rf rendered
mkdir -p rendered

# Inject derived vars for template rendering
export RDD_HOME="$HOME"
export RDD_REPO_DIR="$REPO_DIR"
export RDD_WORKSPACE="$WORKSPACE"
export RDD_LOG="$STATE_DIR/edge-coder-run.log"
export RDD_RUNS_DIR="$STATE_DIR/runs"
export RDD_LOCKDIR="$STATE_DIR/locks"

python3 - "$ENV_FILE" <<'PY'
import os, re, sys, pathlib

env_file = sys.argv[1]
tokens = {}

# First pass: read template.env
for line in open(env_file):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    k, v = k.strip(), v.strip().strip('"').strip("'")
    if k.startswith("RDD_"):
        tokens[k[4:]] = v

# Second pass: inject derived vars
home = os.environ.get("HOME", "")
tokens["HOME"] = home
tokens["WORKSPACE"] = f"{home}/.openclaw/workspace-{tokens.get('AGENT_ID', 'edge')}"
tokens["REPO_DIR"] = f"{tokens['WORKSPACE']}/projects/{tokens.get('PROJECT_SLUG', 'myproject')}"
tokens["LOG"] = f"{home}/.local/state/edge-rdd/edge-coder-run.log"
tokens["RUNS_DIR"] = f"{home}/.local/state/edge-rdd/runs"
tokens["LOCKDIR"] = f"{home}/.local/state/edge-rdd/locks"

# Expand ~ in paths
for k in ["OPENCODE", "OPENCLAW", "PATH_PREPEND"]:
    if k in tokens:
        tokens[k] = tokens[k].replace("~", home)

render_dirs = ["opencode", "openclaw", "workspace-edge", "project-repo"]
token_re = re.compile(r"\{\{([A-Z0-9_]+)\}\}")
missing = set()

for d in render_dirs:
    if not pathlib.Path(d).exists():
        continue
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

if [ "$APPLY" != "1" ]; then
  exit 0
fi

# ---- APPLY -----------------------------------------------------------------
echo "--- applying workspace-first install ---"
echo "Workspace: $WORKSPACE"

# Helper: create symlink idempotently
symlink() { # symlink <target> <link>
  local target="$1" link="$2"
  if [ -L "$link" ]; then
    local current
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      return 0  # already correct
    fi
    rm "$link"
  elif [ -e "$link" ]; then
    # Back up existing file/dir
    local backup="${link}.bak.$(date +%Y%m%d_%H%M%S)"
    mv "$link" "$backup"
    echo "  backed up: $link -> $backup"
  fi
  ln -s "$target" "$link"
}

# 1. Create workspace structure
mkdir -p "$WORKSPACE"/{projects,context,config/edge-rdd,config/opencode/agents,skills,scripts}
mkdir -p "$WORKSPACE/context/${RDD_PROJECT_SLUG}/notes"
mkdir -p "$STATE_DIR"/{runs,locks,pr-gate}

# 2. Workspace docs (SOUL.md, AGENTS.md, etc.)
for f in AGENTS.md HEARTBEAT.md IDENTITY.md SKILL-REGISTRY.md USER.md; do
  if [ -f "rendered/workspace-edge/$f" ]; then
    if [ ! -f "$WORKSPACE/$f" ]; then
      cp "rendered/workspace-edge/$f" "$WORKSPACE/$f"
      echo "  installed: $f"
    else
      echo "  kept existing: $f"
    fi
  fi
done

# PROJECT.md and RESUME.md go into projects/<slug>/
mkdir -p "$WORKSPACE/projects/${RDD_PROJECT_SLUG}"
for f in PROJECT.md RESUME.md; do
  if [ -f "rendered/workspace-edge/$f" ]; then
    if [ ! -f "$WORKSPACE/projects/${RDD_PROJECT_SLUG}/$f" ]; then
      cp "rendered/workspace-edge/$f" "$WORKSPACE/projects/${RDD_PROJECT_SLUG}/$f"
      echo "  installed: projects/${RDD_PROJECT_SLUG}/$f"
    else
      echo "  kept existing: projects/${RDD_PROJECT_SLUG}/$f"
    fi
  fi
done

# SUPERIOR_ARCHITECTURE.md goes into projects/<slug>/notes/
if [ -f "rendered/workspace-edge/SUPERIOR_ARCHITECTURE.md" ]; then
  if [ ! -f "$WORKSPACE/projects/${RDD_PROJECT_SLUG}/notes/SUPERIOR_ARCHITECTURE.md" ]; then
    cp "rendered/workspace-edge/SUPERIOR_ARCHITECTURE.md" "$WORKSPACE/projects/${RDD_PROJECT_SLUG}/notes/SUPERIOR_ARCHITECTURE.md"
    echo "  installed: projects/${RDD_PROJECT_SLUG}/notes/SUPERIOR_ARCHITECTURE.md"
  else
    echo "  kept existing: projects/${RDD_PROJECT_SLUG}/notes/SUPERIOR_ARCHITECTURE.md"
  fi
fi

# 3. Personas
mkdir -p "$WORKSPACE/personas"
if [ -d "rendered/workspace-edge/personas" ]; then
  cp rendered/workspace-edge/personas/*.md "$WORKSPACE/personas/" 2>/dev/null || true
  echo "  installed: personas/"
fi

# SOUL.md from active persona
PERSONA="${RDD_PERSONA:-FRONTIER}"
if [ ! -f "$WORKSPACE/SOUL.md" ] && [ -f "$WORKSPACE/personas/${PERSONA}.md" ]; then
  cp "$WORKSPACE/personas/${PERSONA}.md" "$WORKSPACE/SOUL.md"
  echo "  installed: SOUL.md (from $PERSONA)"
fi

# 4. Templates
if [ -d "rendered/workspace-edge/templates" ]; then
  mkdir -p "$WORKSPACE/templates"
  cp rendered/workspace-edge/templates/* "$WORKSPACE/templates/" 2>/dev/null || true
  echo "  installed: templates/"
fi

# 5. Scripts (workspace-edge/scripts/)
for f in edge-coder-run.sh edge-pr-gate.sh openscience-research.sh openscience-research.py openscience-smoke.sh; do
  if [ -f "scripts/$f" ]; then
    install -m 0755 "scripts/$f" "$WORKSPACE/scripts/$f"
    echo "  installed: scripts/$f"
  fi
done

# 5b. Lab (Docker-based gapped experiment lab)
if [ -d "lab" ]; then
  mkdir -p "$WORKSPACE/lab/experiments"
  for f in lab/*; do
    if [ -f "$f" ]; then
      cp "$f" "$WORKSPACE/$f"
    fi
  done
  chmod +x "$WORKSPACE"/lab/*.sh 2>/dev/null || true
  echo "  installed: lab/ (Docker gapped lab — build image with: lab/lab-run.sh --image)"
fi

# 6. Skills (workspace-edge/skills/<name>/)
for sk in gate research; do
  if [ -d "rendered/openclaw/skills/$sk" ]; then
    mkdir -p "$WORKSPACE/skills/$sk"
    cp "rendered/openclaw/skills/$sk/SKILL.md" "$WORKSPACE/skills/$sk/SKILL.md"
    echo "  installed: skills/$sk/SKILL.md"
  fi
done

# 7. Code-monkeys agents (workspace-edge/config/opencode/agents/code-monkeys/)
if [ -d "rendered/opencode/agents/code-monkeys" ]; then
  mkdir -p "$WORKSPACE/config/opencode/agents/code-monkeys"
  for f in rendered/opencode/agents/code-monkeys/*; do
    cp "$f" "$WORKSPACE/config/opencode/agents/code-monkeys/"
  done
  echo "  installed: config/opencode/agents/code-monkeys/"
fi

# 8. Dispatch config (workspace-edge/config/edge-rdd/config.env)
# config.env is the wrapper's DEFAULT config: the primary project plus the
# single-source model tier ladder. Additional projects get their own
# <slug>.env (copy config.env, adjust the project block) selected per dispatch
# with EDGE_RDD_CONFIG=~/.config/edge-rdd/<slug>.env.
cat > "$CONFIG_DIR/config.env" <<CFGEOF
# Primary project: $RDD_PROJECT_NAME — dispatch config (generated by install.sh)
RDD_OPENCODE=$HOME/.opencode/bin/opencode
RDD_OPENCLAW=$HOME/.local/bin/openclaw
RDD_REPO_DIR=$REPO_DIR
RDD_AGENT=${RDD_AGENT:-code-monkeys/coder}
RDD_MAIN_BRANCH=${RDD_MAIN_BRANCH:-main}
RDD_BRANCH_PREFIX=${RDD_BRANCH_PREFIX:-cm}
RDD_DOCS_DIR=${RDD_DOCS_DIR:-docs/agent}
RDD_LOG=$STATE_DIR/edge-coder-run.log
RDD_RUNS_DIR=$STATE_DIR/runs
RDD_LOCKDIR=$STATE_DIR/locks
RDD_TG_CHANNEL=${RDD_TG_CHANNEL:-telegram}
RDD_TG_TARGET=${RDD_TG_TARGET:-}
RDD_TG_THREAD=${RDD_TG_THREAD:-}
RDD_CI_POLL_SECS=${RDD_CI_POLL_SECS:-60}
RDD_CI_POLL_MAX=${RDD_CI_POLL_MAX:-40}
RDD_PATH_PREPEND=${RDD_PATH_PREPEND:-$HOME/.local/bin}
RDD_GATE_SCRIPT=$HOME/.openclaw/shared-scripts/edge-pr-gate.sh
RDD_REQUIRED_CHECKS="${RDD_REQUIRED_CHECKS:-}"

# ---- model tier ladder (single source of truth — pick your own models) ----
RDD_MODELS="${RDD_MODELS:-}"
# Per-tier LIVENESS-PROBE timeouts (seconds), index-aligned with RDD_MODELS.
RDD_TIMEOUTS_BG="${RDD_TIMEOUTS_BG:-60 60}"
RDD_TIMEOUTS_FG="${RDD_TIMEOUTS_FG:-60 60}"
# Optional opencode model variants, index-aligned with RDD_MODELS.
RDD_VARIANTS="${RDD_VARIANTS:-}"
# static (default) uses RDD_VARIANTS as-is; auto classifies task effort and
# applies the RDD_VARIANTS_<PROFILE> maps below (empty map = keep baseline).
RDD_VARIANT_POLICY=${RDD_VARIANT_POLICY:-static}
RDD_VARIANTS_FAST="${RDD_VARIANTS_FAST:-}"
RDD_VARIANTS_STANDARD="${RDD_VARIANTS_STANDARD:-}"
RDD_VARIANTS_DEEP="${RDD_VARIANTS_DEEP:-}"
RDD_VARIANTS_MAX="${RDD_VARIANTS_MAX:-}"
CFGEOF
echo "  installed: config/edge-rdd/config.env"

# 9. Gate config (workspace-edge/config/edge-rdd/gate.env)
cat > "$CONFIG_DIR/gate.env" <<GATEEOF
# EDGE PR gate — the single hub thread every gate message posts to.
# Generated by install.sh from template.env.
RDD_GATE_TG_CHANNEL=${RDD_GATE_TG_CHANNEL:-${RDD_TG_CHANNEL:-telegram}}
RDD_GATE_TG_TARGET=${RDD_GATE_TG_TARGET:-${RDD_TG_TARGET:-}}
RDD_GATE_TG_THREAD=${RDD_GATE_TG_THREAD:-${RDD_TG_THREAD:-}}
GATEEOF
echo "  installed: config/edge-rdd/gate.env"

# 9b. Research dispatch config (workspace-edge/config/edge-rdd/research.env)
# NOTE: deliberately NO RDD_REPO_DIR here — the PR gate's project sweep keys on
# that variable, so the research config is invisible to it (no second registry).
cat > "$CONFIG_DIR/research.env" <<RESEOF
# OpenScience research dispatch — config for openscience-research.sh
# Default return thread mirrors the PR gate hub; assignments may pass --thread.
RDD_RESEARCH_OS_BASE=${RDD_RESEARCH_OS_BASE:-http://127.0.0.1:3457}
RDD_RESEARCH_AGENT=${RDD_RESEARCH_AGENT:-research}
RDD_RESEARCH_TIMEOUT=${RDD_RESEARCH_TIMEOUT:-1200}
# Provider-specific reasoning variant (empty = provider default).
RDD_RESEARCH_VARIANT=${RDD_RESEARCH_VARIANT:-}
RDD_RESEARCH_TG_CHANNEL=${RDD_GATE_TG_CHANNEL:-${RDD_TG_CHANNEL:-telegram}}
RDD_RESEARCH_TG_TARGET=${RDD_GATE_TG_TARGET:-${RDD_TG_TARGET:-}}
RDD_RESEARCH_TG_THREAD=${RDD_GATE_TG_THREAD:-${RDD_TG_THREAD:-}}
RDD_OPENCLAW=$HOME/.local/bin/openclaw
RESEOF
echo "  installed: config/edge-rdd/research.env"

# 10. Clone project repo if not exists
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "  cloning: $RDD_REPO_URL -> $REPO_DIR"
  git clone "$RDD_REPO_URL" "$REPO_DIR"
else
  echo "  repo exists: $REPO_DIR"
fi

# 11. Seed handoff docs into project repo
if [ -d "$REPO_DIR/.git" ]; then
  mkdir -p "$REPO_DIR/${RDD_DOCS_DIR}"
  for f in rendered/project-repo/docs/agent/*; do
    if [ -f "$f" ]; then
      target="$REPO_DIR/${RDD_DOCS_DIR}/$(basename "$f")"
      if [ ! -f "$target" ]; then
        cp "$f" "$target"
        echo "  seeded: $target"
      fi
    fi
  done
fi

# 12. Create symlinks
echo ""
echo "--- creating symlinks ---"

# ~/.config/edge-rdd -> workspace/config/edge-rdd
symlink "$CONFIG_DIR" "$HOME/.config/edge-rdd"
echo "  symlink: ~/.config/edge-rdd -> workspace/config/edge-rdd"

# ~/.openclaw/skills/<name> -> workspace/skills/<name>
for sk in gate research; do
  symlink "$WORKSPACE/skills/$sk" "$HOME/.openclaw/skills/$sk"
  echo "  symlink: ~/.openclaw/skills/$sk -> workspace/skills/$sk"
done

# ~/.openclaw/shared-scripts/* -> workspace/scripts/*
mkdir -p "$HOME/.openclaw/shared-scripts"
for f in edge-coder-run.sh edge-pr-gate.sh openscience-research.sh openscience-research.py openscience-smoke.sh; do
  symlink "$WORKSPACE/scripts/$f" "$HOME/.openclaw/shared-scripts/$f"
  echo "  symlink: ~/.openclaw/shared-scripts/$f -> workspace/scripts/$f"
done

# ~/.config/opencode/agents/code-monkeys -> workspace/config/opencode/agents/code-monkeys
mkdir -p "$HOME/.config/opencode/agents"
symlink "$WORKSPACE/config/opencode/agents/code-monkeys" "$HOME/.config/opencode/agents/code-monkeys"
echo "  symlink: ~/.config/opencode/agents/code-monkeys -> workspace/config/opencode/agents/code-monkeys"

echo ""
echo "=== WORKSPACE-FIRST INSTALL COMPLETE ==="
echo ""
echo "Workspace: $WORKSPACE"
echo "Project:   $REPO_DIR"
echo "Config:    $CONFIG_DIR/${RDD_PROJECT_SLUG}.env"
echo ""
echo "=== MANUAL STEPS REMAINING ==="
echo "1. Merge rendered/openclaw/agent.edge.json5 into agents.list[] in ~/.openclaw/openclaw.json"
echo "   (its skills[] includes \"gate\" and \"research\" — keep them so /gate and /research work)"
echo "2. Merge rendered/openclaw/topic.project-thread.json5 into your Telegram group's topics map,"
echo "   and rendered/openclaw/topic.hub-thread.json5 for the gate/coordination hub thread"
echo "3. openclaw config validate && systemctl --user restart openclaw-gateway"
echo "4. Copy project-repo/.github/workflows/ci.yml.example into your repo as .github/workflows/ci.yml"
echo "5. bash github/protect-branch.sh (after CI ran once)"
echo "6. Smoke test: bash $WORKSPACE/scripts/edge-coder-run.sh status"
echo "   PR gate:    bash $WORKSPACE/scripts/edge-pr-gate.sh sweep --dry-run"
echo "7. Kick off: bash scripts/kickoff.sh"
echo "8. Build the gapped lab Docker image: cd $WORKSPACE && lab/lab-run.sh --image"
echo "9. OPTIONAL research companion (dual-research protocol): install OpenScience"
echo "   per openscience/README.md, then verify: bash $WORKSPACE/scripts/openscience-smoke.sh --health-only"
echo ""
echo "See docs/SETUP.md for the full walkthrough."
