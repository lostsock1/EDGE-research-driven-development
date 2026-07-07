#!/usr/bin/env bash
# EDGE Gapped Lab — container entrypoint
# Mounted at /lab/experiment/ inside container.
# Expects: /lab/experiment/run.sh or /lab/experiment/run.py
# Protocol file is at /lab/experiment/protocol.yaml (pre-written by lab-run.sh)
set -euo pipefail

EXP_DIR="/lab/experiment"
PROTOCOL="${EXP_DIR}/protocol.yaml"
RESULTS="${EXP_DIR}/results.txt"
EXIT_CODE_FILE="${EXP_DIR}/.exit_code"

echo "=== EDGE Gapped Lab Run ==="
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Protocol: ${PROTOCOL}"
echo ""

# Read and display protocol summary
if [ -f "${PROTOCOL}" ]; then
  echo "--- Protocol ---"
  cat "${PROTOCOL}"
  echo "--- End Protocol ---"
  echo ""
else
  echo "WARNING: No protocol file found at ${PROTOCOL}"
  echo "A pre-registered protocol is required by lab discipline."
fi

mkdir -p "${EXP_DIR}/output"

# Find and run the experiment
if [ -f "${EXP_DIR}/run.sh" ]; then
  echo "Running: ${EXP_DIR}/run.sh"
  cd "${EXP_DIR}" && bash run.sh 2>&1 | tee "${RESULTS}"
  EXIT_CODE=${PIPESTATUS[0]}
elif [ -f "${EXP_DIR}/run.py" ]; then
  echo "Running: ${EXP_DIR}/run.py"
  cd "${EXP_DIR}" && python run.py 2>&1 | tee "${RESULTS}"
  EXIT_CODE=${PIPESTATUS[0]}
else
  echo "ERROR: No run.sh or run.py found in ${EXP_DIR}"
  EXIT_CODE=2
fi

echo "${EXIT_CODE}" > "${EXIT_CODE_FILE}"
echo ""
echo "=== Run Complete ==="
echo "Exit code: ${EXIT_CODE}"
echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

exit ${EXIT_CODE}
