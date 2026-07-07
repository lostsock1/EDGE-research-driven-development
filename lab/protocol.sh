#!/usr/bin/env bash
# protocol.sh — EDGE Gapped Lab pre-registration helper
#
# Interactive or scripted creation of experiment protocols.
# Writes a protocol.yaml that lab-run.sh validates before running.
#
# Usage:
#   protocol.sh --new <slug>     Interactive protocol creation
#   protocol.sh --template       Print a blank protocol template
#   protocol.sh --validate <dir> Validate an existing protocol

set -euo pipefail

LAB_EXPERIMENTS_DIR="${LAB_EXPERIMENTS_DIR:-$(cd "$(dirname "$0")" && pwd)/experiments}"

print_template() {
  cat <<'YAML'
# EDGE Gapped Lab — Experiment Protocol
# Pre-register before running. The lab refuses without hypothesis, rival,
# and refutation_condition filled in. This is the spine — do not skip it.

hypothesis: ""
rival: ""
discrimination: ""
metric: ""
refutation_condition: ""
resource_bound:
  memory: "2g"
  cpus: 2
  timeout_seconds: 600
notes: ""
YAML
}

create_protocol() {
  local slug="$1"
  local exp_dir="${LAB_EXPERIMENTS_DIR}/${slug}"
  mkdir -p "${exp_dir}/output"

  echo "=== EDGE Gapped Lab — Protocol Pre-Registration ==="
  echo "Experiment: ${slug}"
  echo ""
  echo "This is the spine of the gapped lab. Every field must be filled."
  echo "A blank or placeholder answer will be rejected at runtime."
  echo ""

  read -rp "Hypothesis (what you assert): " hypothesis
  read -rp "Rival (the incompatible alternative): " rival
  read -rp "Discrimination (how they predict differently): " discrimination
  read -rp "Metric (measure what you care about): " metric
  read -rp "Refutation condition (result that kills the hypothesis): " refutation
  read -rp "Memory limit [2g]: " memory; memory="${memory:-2g}"
  read -rp "CPU limit [2]: " cpus; cpus="${cpus:-2}"
  read -rp "Timeout seconds [600]: " timeout; timeout="${timeout:-600}"
  read -rp "Notes: " notes

  cat > "${exp_dir}/protocol.yaml" <<YAML
# EDGE Gapped Lab — Experiment Protocol
# Registered: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Experiment: ${slug}

hypothesis: "${hypothesis}"
rival: "${rival}"
discrimination: "${discrimination}"
metric: "${metric}"
refutation_condition: "${refutation}"
resource_bound:
  memory: "${memory}"
  cpus: ${cpus}
  timeout_seconds: ${timeout}
notes: "${notes}"
YAML

  echo ""
  echo "Protocol written: ${exp_dir}/protocol.yaml"
  echo "Next: write your experiment in ${exp_dir}/run.sh"
  echo "Then:  lab-run.sh ${exp_dir}"
}

validate_protocol() {
  local proto="$1/protocol.yaml"
  if [ ! -f "$proto" ]; then
    echo "FAIL: No protocol.yaml in $1"
    exit 1
  fi
  local ok=true
  for field in hypothesis rival refutation_condition; do
    local val
    val=$(grep -E "^${field}:" "$proto" | sed "s/^${field}: *\"\\(.*\\)\"/\\1/" | sed "s/^${field}: *//")
    if [ -z "$val" ] || [ "$val" = '""' ]; then
      echo "FAIL: Empty field: ${field}"
      ok=false
    fi
  done
  if $ok; then
    echo "PASS: protocol.yaml is complete for $1"
  else
    echo ""
    echo "Fill in missing fields and re-validate."
  fi
}

case "${1:-}" in
  --new)
    if [ $# -lt 2 ]; then
      echo "Usage: protocol.sh --new <slug>"
      exit 1
    fi
    create_protocol "$2"
    ;;
  --template)
    print_template
    ;;
  --validate)
    if [ $# -lt 2 ]; then
      echo "Usage: protocol.sh --validate <experiment-dir>"
      exit 1
    fi
    validate_protocol "$2"
    ;;
  *)
    echo "Usage: protocol.sh --new <slug> | --template | --validate <dir>"
    exit 1
    ;;
esac
