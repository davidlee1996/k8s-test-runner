#!/usr/bin/env bash
# entrypoint.sh
#
# Container entrypoint for Week 3. Replaces the simple `npx playwright test` CMD.
#
# Flow:
#   1. Run Playwright tests (capture exit code, don't fail the script yet)
#   2. Upload results to S3 (uploads succeed/fail independently)
#   3. Exit with Playwright's original exit code
#
# Why this matters:
#   - We want results in S3 EVEN WHEN tests fail. The aggregator needs the
#     failure details to produce a useful report.
#   - The Job's success/failure should reflect the TESTS, not the upload.

set -uo pipefail
# Note: NOT `set -e`. We want to capture and propagate Playwright's exit code,
# not let bash bail at the first non-zero return.

echo "════════════════════════════════════════════════════════════"
echo "  Pod: ${POD_NAME:-<unknown>}"
echo "  User: ${SAUCE_USER:-<unset>}"
echo "  Run ID: ${RUN_ID:-<unset>}"
echo "  Bucket: ${S3_BUCKET:-<unset>}"
echo "════════════════════════════════════════════════════════════"

# Run the tests
echo "[entrypoint] Starting Playwright tests..."
npx playwright test
PLAYWRIGHT_EXIT=$?
echo "[entrypoint] Playwright exited with code: ${PLAYWRIGHT_EXIT}"

# Always attempt the upload, regardless of test outcome
echo "[entrypoint] Uploading results to S3..."
node /app/upload-results.js
UPLOAD_EXIT=$?
echo "[entrypoint] Upload exited with code: ${UPLOAD_EXIT}"

# Decide the pod's exit code
if [ "${PLAYWRIGHT_EXIT}" -ne 0 ]; then
  echo "[entrypoint] Exiting with Playwright's code: ${PLAYWRIGHT_EXIT}"
  exit "${PLAYWRIGHT_EXIT}"
fi

if [ "${UPLOAD_EXIT}" -ne 0 ]; then
  echo "[entrypoint] Tests passed but upload failed. Exiting non-zero."
  exit "${UPLOAD_EXIT}"
fi

echo "[entrypoint] ✓ All steps succeeded"
exit 0