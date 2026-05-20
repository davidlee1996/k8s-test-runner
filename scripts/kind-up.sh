#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME="test-runner-dev"
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "✓ Kind cluster '${CLUSTER_NAME}' already exists, skipping creation."
else
  echo "→ Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}"
fi
kubectl config use-context "kind-${CLUSTER_NAME}"
echo "✓ Cluster ready. Context: kind-${CLUSTER_NAME}"