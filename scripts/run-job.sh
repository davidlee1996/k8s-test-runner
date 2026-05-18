#!/usr/bin/env bash
# Apply the Job manifest, wait for it to complete, and tail logs.
#
# Behavior:
# 1. Delete any prior Job with the same name (Jobs are immutable; re-applying
#    a Job without deleting first will error).
# 2. Apply the new Job.
# 3. Wait for the underlying pod to be scheduled.
# 4. Stream pod logs to your terminal.
# 5. Report final Job status (Succeeded / Failed).

set -euo pipefail

JOB_NAME="playwright-runner"
NAMESPACE="default"
TIMEOUT="120s"
MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)/runner-job.yaml"

echo "→ Cleaning up any previous Job named '${JOB_NAME}'..."
kubectl delete job "${JOB_NAME}" --ignore-not-found=true --wait=true

echo "→ Applying Job manifest..."
kubectl apply -f "${MANIFEST}"

echo "→ Waiting for pod to be scheduled..."
# Get the pod name. Brief retry loop because pod creation isn't instant.
POD_NAME=""
for i in {1..20}; do
  POD_NAME=$(kubectl get pods --selector=job-name="${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "${POD_NAME}" ]; then
    break
  fi
  sleep 1
done

if [ -z "${POD_NAME}" ]; then
  echo "✗ Pod did not appear within 20 seconds. Debug with:"
  echo "    kubectl describe job ${JOB_NAME}"
  echo "    kubectl get events --sort-by='.lastTimestamp'"
  exit 1
fi

echo "✓ Pod '${POD_NAME}' scheduled. Streaming logs..."
echo "----------------------------------------"

# `kubectl logs -f` will block until the pod exits, streaming output as it arrives.
# Wrapping in `|| true` because if the pod exits with non-zero, we still want to
# get to the status check below.
kubectl logs -f "${POD_NAME}" || true

echo "----------------------------------------"

# Wait for the Job to officially complete (Succeeded or Failed).
# The pod could be done while the Job controller hasn't updated status yet.
echo "→ Waiting for Job status update..."
kubectl wait --for=condition=complete --timeout="${TIMEOUT}" "job/${JOB_NAME}" 2>/dev/null && \
  JOB_STATUS="succeeded" || JOB_STATUS="failed"

if [ "${JOB_STATUS}" = "succeeded" ]; then
  echo "✅ Job succeeded."
  exit 0
else
  echo "❌ Job failed. Inspect with:"
  echo "    kubectl describe job ${JOB_NAME}"
  echo "    kubectl logs ${POD_NAME}"
  exit 1
fi