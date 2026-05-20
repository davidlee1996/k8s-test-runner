#!/usr/bin/env bash
# create-secret.sh
#
# Creates the K8s Secret holding AWS credentials and S3 config.
# Reads from ~/.k8s-test-runner-credentials.

set -euo pipefail

CREDS_FILE="${HOME}/.k8s-test-runner-credentials"
SECRET_NAME="aws-credentials"

if [ ! -f "${CREDS_FILE}" ]; then
  echo "✗ Credentials file not found: ${CREDS_FILE}"
  echo ""
  echo "Run through docs/AWS_SETUP.md first to create your IAM user and bucket."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${CREDS_FILE}"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set in ${CREDS_FILE}}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set in ${CREDS_FILE}}"
: "${S3_BUCKET:?S3_BUCKET not set in ${CREDS_FILE}}"
: "${AWS_REGION:?AWS_REGION not set in ${CREDS_FILE}}"

echo "→ Recreating secret '${SECRET_NAME}'..."
kubectl delete secret "${SECRET_NAME}" --ignore-not-found=true

kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=S3_BUCKET="${S3_BUCKET}" \
  --from-literal=AWS_REGION="${AWS_REGION}"

echo "✓ Secret created. Bucket: ${S3_BUCKET}, Region: ${AWS_REGION}"