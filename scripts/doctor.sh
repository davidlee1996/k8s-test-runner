#!/usr/bin/env bash
# doctor.sh
#
# Verifies that everything needed for Week 3 is in place.
# Run this before `make demo` if anything seems off.

set -uo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local cmd="$2"
  if eval "${cmd}" > /dev/null 2>&1; then
    echo "  ✓ ${label}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${label}"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══════════════════════════════════════════════════════"
echo "  k8s-test-runner Week 3 health check"
echo "═══════════════════════════════════════════════════════"

echo ""
echo "Tools installed:"
check "docker"   "docker --version"
check "kind"     "kind --version"
check "kubectl"  "kubectl version --client"
check "aws"      "aws --version"
check "envsubst" "envsubst --version"
check "node"     "node --version"

echo ""
echo "AWS credentials file:"
CREDS_FILE="${HOME}/.k8s-test-runner-credentials"
if [ -f "${CREDS_FILE}" ]; then
  echo "  ✓ ${CREDS_FILE} exists"
  PASS=$((PASS + 1))

  set -a; source "${CREDS_FILE}"; set +a

  check "  AWS_ACCESS_KEY_ID set"     "[ -n \"\${AWS_ACCESS_KEY_ID:-}\" ]"
  check "  AWS_SECRET_ACCESS_KEY set" "[ -n \"\${AWS_SECRET_ACCESS_KEY:-}\" ]"
  check "  S3_BUCKET set"             "[ -n \"\${S3_BUCKET:-}\" ]"
  check "  AWS_REGION set"            "[ -n \"\${AWS_REGION:-}\" ]"
else
  echo "  ✗ ${CREDS_FILE} not found"
  echo "    → Walk through docs/AWS_SETUP.md first"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "AWS connectivity:"
if [ -n "${S3_BUCKET:-}" ]; then
  check "Can list S3 bucket" "aws s3 ls s3://${S3_BUCKET}/"
fi

echo ""
echo "Kind cluster:"
if kind get clusters 2>/dev/null | grep -q "test-runner-dev"; then
  echo "  ✓ Kind cluster 'test-runner-dev' exists"
  PASS=$((PASS + 1))

  check "kubectl can reach cluster" "kubectl get nodes"
  check "Image loaded in cluster"   "docker exec test-runner-dev-control-plane crictl images 2>/dev/null | grep -q k8s-test-runner"
  check "Secret 'aws-credentials' exists" "kubectl get secret aws-credentials"
else
  echo "  ⚠ Kind cluster not running (run 'make cluster-up')"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════════"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi