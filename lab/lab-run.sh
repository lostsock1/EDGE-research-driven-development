#!/usr/bin/env bash
# lab-run.sh — EDGE Gapped Lab dispatcher
#
# Runs a contained Docker experiment. Creates a fresh container per run,
# enforces the pre-registration protocol, captures results, tears down.
#
# Usage:
#   lab-run.sh <experiment-dir>                    # Run from pre-filled dir
#   lab-run.sh --new <slug> [--template <type>]   # Create from template
#   lab-run.sh --protocol <yaml> --script <file>   # One-shot: write protocol + script, run
#   lab-run.sh --image                            # Build/rebuild the lab image
#   lab-run.sh --clean                             # Remove all experiment artifacts
#
# Environment (all optional, with defaults):
#   LAB_IMAGE=edge-gapped-lab:latest
#   LAB_MEMORY=2g
#   LAB_CPUS=2
#   LAB_TIMEOUT=600          # seconds
#   LAB_NETWORK=none         # none|bridge|host
#   LAB_WORKSPACE=<auto>     # workspace-edge root
#   LAB_EXPERIMENTS_DIR=<auto>  # where experiment dirs live
#
# Protocol: each experiment dir must contain protocol.yaml before run.
# The lab-run.sh refuses to run without one (use --force to override).
#
# Part of EDGE — Evidence-Driven Git Engineering.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_IMAGE="${LAB_IMAGE:-edge-gapped-lab:latest}"
LAB_MEMORY="${LAB_MEMORY:-2g}"
LAB_CPUS="${LAB_CPUS:-2}"
LAB_TIMEOUT="${LAB_TIMEOUT:-600}"
LAB_NETWORK="${LAB_NETWORK:-none}"
LAB_WORKSPACE="${LAB_WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LAB_EXPERIMENTS_DIR="${LAB_EXPERIMENTS_DIR:-${LAB_WORKSPACE}/lab/experiments}"
FORCE="${FORCE:-0}"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
red()  { echo -e "\033[31m$*\033[0m"; }
green(){ echo -e "\033[32m$*\033[0m"; }
bold() { echo -e "\033[1m$*\033[0m"; }

usage() {
  cat <<EOF
$(bold "EDGE Gapped Lab — lab-run.sh")

$(bold "USAGE")
  lab-run.sh <experiment-dir>            Run a pre-filled experiment directory
  lab-run.sh --new <slug>                Create a new experiment from template
  lab-run.sh --protocol <file> --script <file>  One-shot: write protocol + script, run
  lab-run.sh --image                     Build/rebuild lab Docker image
  lab-run.sh --clean                     Remove all experiment artifacts
  lab-run.sh --list                      List past experiments

$(bold "PROTOCOL REQUIREMENT")
  Every experiment dir MUST contain a protocol.yaml with at minimum:
    hypothesis, rival, refutation_condition
  The lab refuses to run without one (use FORCE=1 to bypass — not recommended).

$(bold "ENVIRONMENT")
  LAB_IMAGE       Docker image tag (default: edge-gapped-lab:latest)
  LAB_MEMORY      Container memory limit (default: 2g)
  LAB_CPUS        Container CPU limit (default: 2)
  LAB_TIMEOUT     Container timeout in seconds (default: 600)
  LAB_NETWORK     Docker network mode (default: none)
  LAB_WORKSPACE   Workspace root (default: parent of this script)
  LAB_EXPERIMENTS_DIR  Where experiments live (default: \$LAB_WORKSPACE/lab/experiments)
EOF
  exit 0
}

# ---- build the lab image ----
build_image() {
  echo "[$(ts)] Building lab image: ${LAB_IMAGE}"
  docker build -t "${LAB_IMAGE}" "${SCRIPT_DIR}"
  echo "[$(ts)] Image built: ${LAB_IMAGE}"
}

# ---- list past experiments ----
list_experiments() {
  if [ ! -d "${LAB_EXPERIMENTS_DIR}" ]; then
    echo "No experiments directory yet: ${LAB_EXPERIMENTS_DIR}"
    return
  fi
  echo "Experiments in ${LAB_EXPERIMENTS_DIR}:"
  for d in "${LAB_EXPERIMENTS_DIR}"/*/; do
    [ -d "$d" ] || continue
    local name=$(basename "$d")
    local proto="${d}protocol.yaml"
    local results="${d}results.txt"
    local exit_f="${d}.exit_code"
    echo ""
    echo "  $(bold "$name")"
    if [ -f "$proto" ]; then
      echo "    protocol: yes"
      grep -E '^(hypothesis|rival|refutation_condition):' "$proto" 2>/dev/null | sed 's/^/      /' || true
    else
      echo "    protocol: $(red MISSING)"
    fi
    if [ -f "$exit_f" ]; then
      local ec=$(cat "$exit_f")
      if [ "$ec" = "0" ]; then
        echo "    result: $(green "exit 0")"
      else
        echo "    result: $(red "exit $ec")"
      fi
    else
      echo "    result: unknown"
    fi
  done
}

# ---- create a new experiment dir from template ----
create_experiment() {
  local slug="$1"
  local exp_dir="${LAB_EXPERIMENTS_DIR}/${slug}"
  if [ -d "$exp_dir" ]; then
    echo "Experiment directory already exists: ${exp_dir}"
    exit 1
  fi
  mkdir -p "${exp_dir}/output"
  cat > "${exp_dir}/protocol.yaml" <<'YAML'
# EDGE Gapped Lab — Experiment Protocol
# Fill in ALL fields before running. The lab refuses without them.

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
  cat > "${exp_dir}/run.sh" <<'SH'
#!/usr/bin/env bash
# Experiment script — replace with your experiment.
# Runs inside the lab container with network=none.
# Results written to stdout are captured to results.txt.
# Output files go in ./output/

set -euo pipefail
echo "Experiment placeholder — replace run.sh with your experiment."
SH
  chmod +x "${exp_dir}/run.sh"
  echo "Created experiment: ${exp_dir}"
  echo "  protocol.yaml  — fill in hypothesis, rival, refutation_condition"
  echo "  run.sh         — your experiment script"
  echo "  output/        — results land here"
  echo ""
  echo "When ready: lab-run.sh ${exp_dir}"
}

# ---- validate protocol ----
validate_protocol() {
  local proto="$1"
  if [ ! -f "$proto" ]; then
    red "ERROR: No protocol.yaml found in experiment directory."
    echo "Create one with: lab-run.sh --new <slug>"
    echo "Or bypass with: FORCE=1 lab-run.sh <dir>"
    exit 3
  fi
  local missing=0
  for field in hypothesis rival refutation_condition; do
    local val=$(grep -E "^${field}:" "$proto" | sed "s/^${field}: *\"\\(.*\\)\"/\\1/" | sed "s/^${field}: *//")
    if [ -z "$val" ] || [ "$val" = '""' ] || [ "$val" = '""' ]; then
      red "ERROR: protocol.yaml missing or empty field: ${field}"
      missing=1
    fi
  done
  if [ "$missing" = "1" ] && [ "$FORCE" != "1" ]; then
    echo ""
    echo "The pre-registration protocol is the spine of the gapped lab."
    echo "Fill in hypothesis, rival, and refutation_condition before running."
    echo "Override with FORCE=1 lab-run.sh <dir> (not recommended)."
    exit 3
  fi
  if [ "$missing" = "1" ]; then
    echo "WARNING: Running without complete protocol (FORCE=1). Results are unreliable."
  fi
}

# ---- run experiment ----
run_experiment() {
  local exp_dir
  exp_dir="$(cd "$1" && pwd)"
  local exp_name
  exp_name="$(basename "$exp_dir")"

  validate_protocol "${exp_dir}/protocol.yaml"

  echo "[$(ts)] Starting experiment: ${exp_name}"
  bold "=== Gapped Lab: ${exp_name} ==="
  echo ""

  # Display protocol summary
  echo "Protocol:"
  grep -E '^(hypothesis|rival|discrimination|metric|refutation_condition):' "${exp_dir}/protocol.yaml" | sed 's/^/  /'
  echo ""

  # Run container
  local container_name="edge-lab-${exp_name}"
  # Clean up any previous container with same name
  docker rm -f "${container_name}" 2>/dev/null || true

  echo "[$(ts)] Launching container: ${container_name}"
  echo "  image:   ${LAB_IMAGE}"
  echo "  memory:  ${LAB_MEMORY}"
  echo "  cpus:    ${LAB_CPUS}"
  echo "  timeout: ${LAB_TIMEOUT}s"
  echo "  network: ${LAB_NETWORK}"
  echo ""

  local start_ts=$(date +%s)

  set +e
  docker run \
    --name "${container_name}" \
    --rm \
    --network "${LAB_NETWORK}" \
    --memory "${LAB_MEMORY}" \
    --cpus "${LAB_CPUS}" \
    --hostname "lab-${exp_name}" \
    --user "$(id -u):$(id -g)" \
    -v "${exp_dir}:/lab/experiment:rw" \
    -v "${LAB_WORKSPACE}/projects:/lab/workspace/projects:ro" \
    "${LAB_IMAGE}" \
    2>&1 | tee "${exp_dir}/container.log"
  local exit_code=${PIPESTATUS[0]}
  set -e

  local end_ts=$(date +%s)
  local duration=$((end_ts - start_ts))

  # Record exit code
  echo "${exit_code}" > "${exp_dir}/.exit_code"

  echo ""
  echo "[$(ts)] Experiment complete: ${exp_name}"
  echo "  duration:  ${duration}s"
  echo "  exit code: ${exit_code}"
  echo "  container: ${container_name} (auto-removed)"

  # Enforce timeout
  if [ "${duration}" -gt "${LAB_TIMEOUT}" ]; then
    red "  WARNING: Run exceeded timeout budget (${LAB_TIMEOUT}s)."
  fi

  # Honor pre-commitment
  if [ -f "${exp_dir}/protocol.yaml" ]; then
    local refutation
    refutation=$(grep '^refutation_condition:' "${exp_dir}/protocol.yaml" | sed 's/^refutation_condition: *"\(.*\)"/\1/' | sed 's/^refutation_condition: *//')
    if [ -n "$refutation" ]; then
      echo "  refutation condition: ${refutation}"
      echo "  --> Record this result against the pre-commitment."
    fi
  fi

  echo ""
  bold "Output files:"
  echo "  results:     ${exp_dir}/results.txt"
  echo "  container:   ${exp_dir}/container.log"
  echo "  output dir:  ${exp_dir}/output/"

  return "${exit_code}"
}

# ---- clean ----
clean_experiments() {
  if [ ! -d "${LAB_EXPERIMENTS_DIR}" ]; then
    echo "No experiments directory."
    return
  fi
  echo "This will remove ALL experiment artifacts in: ${LAB_EXPERIMENTS_DIR}"
  echo "Results recorded in project notes are not affected."
  read -rp "Proceed? [y/N] " confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    rm -rf "${LAB_EXPERIMENTS_DIR}"
    echo "Cleaned."
  else
    echo "Aborted."
  fi
}

# ---- main ----
main() {
  if [ $# -eq 0 ]; then
    usage
  fi

  case "${1:-}" in
    --help|-h)
      usage
      ;;
    --image)
      build_image
      ;;
    --list)
      list_experiments
      ;;
    --clean)
      clean_experiments
      ;;
    --new)
      if [ $# -lt 2 ]; then
        echo "Usage: lab-run.sh --new <slug>"
        exit 1
      fi
      mkdir -p "${LAB_EXPERIMENTS_DIR}"
      create_experiment "$2"
      ;;
    --protocol)
      if [ $# -lt 4 ] || [ "$3" != "--script" ]; then
        echo "Usage: lab-run.sh --protocol <yaml-file> --script <run-file> [--slug <name>]"
        exit 1
      fi
      local proto_file="$2"
      local script_file="$4"
      local slug="${6:-exp-$(date +%Y%m%d-%H%M%S)}"
      local exp_dir="${LAB_EXPERIMENTS_DIR}/${slug}"
      mkdir -p "${exp_dir}/output"
      cp "$proto_file" "${exp_dir}/protocol.yaml"
      cp "$script_file" "${exp_dir}/run.sh"
      chmod +x "${exp_dir}/run.sh"
      run_experiment "$exp_dir"
      ;;
    *)
      # Assume it's an experiment directory path
      local exp_dir="$1"
      if [ ! -d "$exp_dir" ]; then
        red "ERROR: Directory not found: ${exp_dir}"
        echo "Create one with: lab-run.sh --new <slug>"
        exit 1
      fi
      run_experiment "$exp_dir"
      ;;
  esac
}

main "$@"
