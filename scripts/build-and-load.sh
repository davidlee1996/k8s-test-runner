#!/usr/bin/env bash
# Build the runner image and load it into the Kind cluster.
# No --platform flag — Docker picks the host arch (amd64 in Codespaces, arm64 on Apple Silicon).

set -euo pipefail

CLUSTER_NAME="test-runner-dev"
IMAGE_NAME="k8s-test-runner:dev"
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../runner" && pwd)"

echo "→ Building image '${IMAGE_NAME}' from ${RUNNER_DIR}..."
docker buildx build \
  --tag "${IMAGE_NAME}" \
  --load \
  "${RUNNER_DIR}"

echo "→ Loading image into Kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

echo "✓ Image built and loaded."