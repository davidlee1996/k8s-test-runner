#!/usr/bin/env bash
# run-jobs.sh
#
# Renders and applies one Job per Sauce demo user (4 total), waits for all of them
# to complete, then triggers result aggregation.

set -euo pipefail

# Generate a unique run ID. Format: YYYYMMDD-HHMMSS-shortrand
RUN_ID="$(date +%Y%m%d-%H%M%S)-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
echo "═════════════════════════════════════════════════════════"
echo "  RUN_ID: ${RUN_ID}"
echo "═════════════════════════════════════════════════════════"

echo "${RUN_ID}" > /tmp/k8s-test-runner-last-run-id

USERS=(STANDARD LOCKED_OUT PROBLEM PERFORMANCE_GLITCH)
TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)/runner-job.template.yaml"

echo "→ Cleaning up any prior playwright-* Jobs..."
kubectl delete jobs -l app=k8s-test-runner --ignore-not-found=true --wait=true

for SAUCE_USER in "${USERS[@]}"; do
  SAUCE_USER_LOWER="$(echo "${SAUCE_USER}" | tr '[:upper:]_' '[:lower:]-')"
  echo "→ Applying Job for user: ${SAUCE_USER}"

  export RUN_ID SAUCE_USER SAUCE_USER_LOWER
  envsubst < "${TEMPLATE}" | kubectl apply -f -
done

echo ""
echo "→ All Jobs applied. Waiting for completion (timeout: 5 minutes)..."

TIMEOUT_SECS=300
ELAPSED=0
INTERVAL=5

while [ "${ELAPSED}" -lt "${TIMEOUT_SECS}" ]; do
  COMPLETE_OR_FAILED=$(kubectl get jobs -l "run-id=${RUN_ID}" \
    -o jsonpath='{range .items[?(@.status.succeeded==1)]}succeeded{"\n"}{end}{range .items[?(@.status.failed>=1)]}failed{"\n"}{end}' \
    2>/dev/null | wc -l | tr -d ' ')

  TOTAL=$(kubectl get jobs -l "run-id=${RUN_ID}" -o jsonpath='{.items[*].metadata.name}' | wc -w | tr -d ' ')

  if [ "${COMPLETE_OR_FAILED}" -ge "${TOTAL}" ] && [ "${TOTAL}" -gt 0 ]; then
    echo "✓ All ${TOTAL} Jobs reached terminal state"
    break
  fi

  echo "  ... ${COMPLETE_OR_FAILED}/${TOTAL} Jobs complete (${ELAPSED}s elapsed)"
  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "${ELAPSED}" -ge "${TIMEOUT_SECS}" ]; then
  echo "✗ Timeout waiting for Jobs. Check with: kubectl get jobs -l run-id=${RUN_ID}"
  exit 1
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo "  Final Job status:"
echo "─────────────────────────────────────────────────────────"
kubectl get jobs -l "run-id=${RUN_ID}" \
  -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.succeeded,FAILED:.status.failed,DURATION:.status.completionTime'

echo ""
echo "Run ID: ${RUN_ID}"
echo "Aggregate results: make aggregate"