#!/usr/bin/env bash
# Create the local Kind cluster used for development.
#
# Idempotent: if the cluster already exists, this script exits cleanly.
# Naming convention: `test-runner-dev` distinguishes it from any other Kind
# clusters you might have for other projects.

set -euo pipefail

CLUSTER_NAME="test-runner-dev"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "✓ Kind cluster '${CLUSTER_NAME}' already exists, skipping creation."
else
  echo "→ Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}"
fi

# Switch kubectl context to this cluster so subsequent commands target it.
kubectl config use-context "kind-${CLUSTER_NAME}"

echo "✓ Cluster ready. Context: kind-${CLUSTER_NAME}"
kubectl cluster-info