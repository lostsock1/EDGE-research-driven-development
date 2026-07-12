#!/usr/bin/env bash
# uninstall.sh — remove EDGE workspace-first scaffolding.
#
#   ./uninstall.sh              remove symlinks only (safe, reversible)
#   ./uninstall.sh --purge      remove workspace-edge too (keeps project repos)
#   ./uninstall.sh --purge-all  remove everything including project repos
#
# The template repo (this directory) is never removed by this script.

set -euo pipefail
cd "$(dirname "$0")"

# Read agent id from template.env if available, default to 'edge'
AGENT_ID="edge"
if [ -f template.env ]; then
  # shellcheck disable=SC1091
  AGENT_ID=$(grep '^RDD_AGENT_ID=' template.env | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "edge")
fi

WORKSPACE="$HOME/.openclaw/workspace-${AGENT_ID}"
STATE_DIR="$HOME/.local/state/edge-rdd"

MODE="${1:-symlinks}"

echo "EDGE uninstall — mode: $MODE"
echo "Workspace: $WORKSPACE"
echo ""

# ---- STEP 1: Remove symlinks -----------------------------------------------
echo "--- removing symlinks ---"

remove_symlink() {
  local link="$1"
  if [ -L "$link" ]; then
    rm "$link"
    echo "  removed: $link"
  elif [ -e "$link" ]; then
    echo "  SKIP (not a symlink, real file/dir): $link"
  else
    echo "  already gone: $link"
  fi
}

# ~/.config/edge-rdd
remove_symlink "$HOME/.config/edge-rdd"

# ~/.openclaw/skills/{gate,research}
remove_symlink "$HOME/.openclaw/skills/gate"
remove_symlink "$HOME/.openclaw/skills/research"

# ~/.openclaw/shared-scripts/*
remove_symlink "$HOME/.openclaw/shared-scripts/edge-coder-run.sh"
remove_symlink "$HOME/.openclaw/shared-scripts/edge-pr-gate.sh"
remove_symlink "$HOME/.openclaw/shared-scripts/openscience-research.sh"
remove_symlink "$HOME/.openclaw/shared-scripts/openscience-research.py"
remove_symlink "$HOME/.openclaw/shared-scripts/openscience-smoke.sh"

# ~/.config/opencode/agents/code-monkeys
remove_symlink "$HOME/.config/opencode/agents/code-monkeys"

# ---- STEP 2: Optionally remove workspace -----------------------------------
if [ "$MODE" = "--purge" ] || [ "$MODE" = "--purge-all" ]; then
  echo ""
  echo "--- removing workspace ---"
  if [ -d "$WORKSPACE" ]; then
    if [ "$MODE" = "--purge-all" ]; then
      rm -rf "$WORKSPACE"
      echo "  removed: $WORKSPACE (including project repos)"
    else
      # Keep project repos, remove everything else
      if [ -d "$WORKSPACE/projects" ]; then
        # Move projects to temp, nuke workspace, move projects back
        tmp=$(mktemp -d)
        mv "$WORKSPACE/projects" "$tmp/projects"
        rm -rf "$WORKSPACE"
        mkdir -p "$HOME/.openclaw"
        mv "$tmp/projects" "$WORKSPACE/projects" 2>/dev/null || true
        echo "  removed: $WORKSPACE (kept project repos in $WORKSPACE/projects/)"
      else
        rm -rf "$WORKSPACE"
        echo "  removed: $WORKSPACE"
      fi
    fi
  else
    echo "  workspace already gone: $WORKSPACE"
  fi

  # Remove state dir
  if [ -d "$STATE_DIR" ]; then
    rm -rf "$STATE_DIR"
    echo "  removed: $STATE_DIR"
  fi
fi

echo ""
echo "=== UNINSTALL COMPLETE ==="
echo ""
if [ "$MODE" = "symlinks" ]; then
  echo "Symlinks removed. Workspace intact at: $WORKSPACE"
  echo "To remove workspace too: ./uninstall.sh --purge"
  echo "To remove everything:    ./uninstall.sh --purge-all"
elif [ "$MODE" = "--purge" ]; then
  echo "Workspace removed. Project repos preserved at: $WORKSPACE/projects/"
  echo "To remove project repos too: ./uninstall.sh --purge-all"
else
  echo "Everything removed. The template repo (this directory) is untouched."
fi
