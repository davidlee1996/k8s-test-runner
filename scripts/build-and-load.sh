#!/usr/bin/env bash
# build-and-load.sh
#
# Builds the runner image and loads it into the Kind cluster.
#
# Architecture: we no longer pin --platform. Docker picks the host arch
# automatically. On Codespaces (x86_64), this builds amd64; on Apple Silicon
# locally, it builds arm64. Both work.
#
# For multi-arch (Week 5, when we push to ECR for EKS), we'll add
# --platform linux/amd64,linux/arm64 in a separate push script.

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