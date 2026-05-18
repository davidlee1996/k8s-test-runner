#!/usr/bin/env bash
# Tear down the local Kind cluster.
#
# Use this when you're done developing for the day or want a clean slate.
# Kind clusters consume meaningful Docker resources even when idle (especially
# memory). Tearing down between sessions is a good habit.

set -euo pipefail

CLUSTER_NAME="test-runner-dev"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "→ Deleting Kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "✓ Cluster deleted."
else
  echo "✓ No cluster named '${CLUSTER_NAME}' found — nothing to do."
fi