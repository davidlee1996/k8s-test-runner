#!/usr/bin/env node
// @ts-check
/**
 * upload-results.js
 *
 * Runs after Playwright finishes (whether tests passed or failed). Uploads the
 * test results JSON to S3 with a structured key that the aggregator can find.
 *
 * Key structure:
 *   runs/<RUN_ID>/<SAUCE_USER>/<POD_NAME>/results.json
 *
 *   RUN_ID      — shared across all pods in a single Job (passed via env var)
 *   SAUCE_USER  — which user this pod tested (STANDARD, PROBLEM, etc.)
 *   POD_NAME    — unique per pod, prevents collisions
 *
 * Env vars (set in the K8s Job spec):
 *   S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
 *   RUN_ID, SAUCE_USER, POD_NAME, PLAYWRIGHT_OUTPUT_DIR
 */

const fs = require('fs');
const path = require('path');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const REQUIRED_ENV = [
  'S3_BUCKET',
  'AWS_REGION',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'RUN_ID',
  'SAUCE_USER',
  'POD_NAME',
  'PLAYWRIGHT_OUTPUT_DIR',
];

function checkEnv() {
  const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    console.error(`[upload] Missing required env vars: ${missing.join(', ')}`);
    process.exit(2);
  }
}

async function uploadResults() {
  checkEnv();

  const {
    S3_BUCKET,
    AWS_REGION,
    RUN_ID,
    SAUCE_USER,
    POD_NAME,
    PLAYWRIGHT_OUTPUT_DIR,
  } = process.env;

  const resultsPath = path.join(PLAYWRIGHT_OUTPUT_DIR, 'results.json');

  let body;
  let contentType;

  if (fs.existsSync(resultsPath)) {
    body = fs.readFileSync(resultsPath, 'utf-8');
    contentType = 'application/json';
    console.log(`[upload] Found results.json (${body.length} bytes)`);
  } else {
    body = JSON.stringify({
      error: 'playwright did not produce results.json',
      user: SAUCE_USER,
      pod: POD_NAME,
      runId: RUN_ID,
      timestamp: new Date().toISOString(),
    });
    contentType = 'application/json';
    console.warn(`[upload] No results.json found at ${resultsPath}; uploading crash marker`);
  }

  const key = `runs/${RUN_ID}/${SAUCE_USER}/${POD_NAME}/results.json`;

  const client = new S3Client({ region: AWS_REGION });

  console.log(`[upload] PUT s3://${S3_BUCKET}/${key}`);
  try {
    await client.send(new PutObjectCommand({
      Bucket: S3_BUCKET,
      Key: key,
      Body: body,
      ContentType: contentType,
      Metadata: {
        'sauce-user': SAUCE_USER,
        'pod-name': POD_NAME,
        'run-id': RUN_ID,
      },
    }));
    console.log(`[upload] ✓ Uploaded successfully`);
  } catch (err) {
    console.error(`[upload] ✗ Upload failed: ${err.message}`);
    process.exit(3);
  }
}

uploadResults().catch((err) => {
  console.error(`[upload] Unexpected error: ${err.stack || err.message}`);
  process.exit(1);
});