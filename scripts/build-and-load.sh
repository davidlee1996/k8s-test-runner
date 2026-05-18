#!/usr/bin/env bash
# Build the runner Docker image and load it into the Kind cluster.
#
# Why kind load:
# Kind clusters can't see images on your local Docker daemon by default.
# `kind load docker-image` copies an image from your local Docker into Kind's
# internal registry. This is the development workflow for Kind.
#
# For EKS in Week 5, this is replaced by `docker push` to ECR + pulling at
# scheduling time. The architecture stays the same; only the image source changes.

set -euo pipefail

CLUSTER_NAME="test-runner-dev"
IMAGE_NAME="k8s-test-runner:dev"
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../runner" && pwd)"

echo "→ Building image '${IMAGE_NAME}' from ${RUNNER_DIR}..."

# Build for linux/arm64 specifically because we're on Apple Silicon and Kind
# nodes will be arm64. --load brings the image into our local Docker daemon
# so kind can pick it up.
#
# In Week 5 (EKS), we'll switch to --platform linux/amd64,linux/arm64 and --push
# to ECR for multi-arch support across the cluster.
docker buildx build \
  --platform linux/arm64 \
  --tag "${IMAGE_NAME}" \
  --load \
  "${RUNNER_DIR}"

echo "→ Loading image into Kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

echo "✓ Image built and loaded."