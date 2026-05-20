#!/usr/bin/env node
// @ts-check
/**
 * aggregate-results.js
 *
 * Lists all result JSON files for a given RUN_ID in S3, downloads them, and
 * prints a unified pass/fail summary.
 *
 * Usage:
 *   node aggregate-results.js [RUN_ID]
 *
 * If RUN_ID is omitted, uses /tmp/k8s-test-runner-last-run-id.
 */

const fs = require('fs');
const { S3Client, ListObjectsV2Command, GetObjectCommand } = require('@aws-sdk/client-s3');

function getRunId() {
  const argRunId = process.argv[2];
  if (argRunId) return argRunId;

  const lastRunFile = '/tmp/k8s-test-runner-last-run-id';
  if (fs.existsSync(lastRunFile)) {
    return fs.readFileSync(lastRunFile, 'utf-8').trim();
  }

  console.error('Usage: node aggregate-results.js [RUN_ID]');
  console.error('No RUN_ID provided and no /tmp/k8s-test-runner-last-run-id found.');
  process.exit(2);
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf-8');
}

async function main() {
  const RUN_ID = getRunId();
  const { S3_BUCKET, AWS_REGION } = process.env;

  if (!S3_BUCKET || !AWS_REGION) {
    console.error('S3_BUCKET and AWS_REGION must be set.');
    console.error('Hint: `source ~/.k8s-test-runner-credentials && export S3_BUCKET AWS_REGION ...`');
    process.exit(2);
  }

  const client = new S3Client({ region: AWS_REGION });
  const prefix = `runs/${RUN_ID}/`;

  console.log(`═══════════════════════════════════════════════════════`);
  console.log(`  Aggregating results for run: ${RUN_ID}`);
  console.log(`  Bucket: ${S3_BUCKET}`);
  console.log(`  Prefix: ${prefix}`);
  console.log(`═══════════════════════════════════════════════════════`);

  const listResp = await client.send(new ListObjectsV2Command({
    Bucket: S3_BUCKET,
    Prefix: prefix,
  }));

  const objects = listResp.Contents || [];
  if (objects.length === 0) {
    console.error(`No results found at s3://${S3_BUCKET}/${prefix}`);
    console.error('Did the runs complete? Check `kubectl get jobs -l run-id=' + RUN_ID + '`');
    process.exit(1);
  }

  console.log(`\nFound ${objects.length} result files:\n`);

  const allResults = [];
  for (const obj of objects) {
    const getResp = await client.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: obj.Key,
    }));
    const body = await streamToString(getResp.Body);
    const parsed = JSON.parse(body);

    const parts = obj.Key.split('/');
    const user = parts[2];
    const pod = parts[3];

    allResults.push({ user, pod, key: obj.Key, data: parsed });
  }

  const perUser = {};
  let totalPassed = 0;
  let totalFailed = 0;
  let totalSkipped = 0;

  for (const result of allResults) {
    const { user, pod, data } = result;

    if (data.error) {
      perUser[user] = { pod, status: 'crashed', message: data.error };
      continue;
    }

    const stats = data.stats || {};
    const passed = stats.expected || 0;
    const failed = stats.unexpected || 0;
    const skipped = stats.skipped || 0;
    const flaky = stats.flaky || 0;
    const durationMs = stats.duration || 0;

    perUser[user] = {
      pod,
      status: failed > 0 ? 'failed' : 'passed',
      passed,
      failed,
      skipped,
      flaky,
      durationSec: (durationMs / 1000).toFixed(1),
    };

    totalPassed += passed;
    totalFailed += failed;
    totalSkipped += skipped;
  }

  console.log('Per-user breakdown:');
  console.log('───────────────────────────────────────────────────────');
  const userOrder = ['STANDARD', 'LOCKED_OUT', 'PROBLEM', 'PERFORMANCE_GLITCH'];
  for (const user of userOrder) {
    const r = perUser[user];
    if (!r) {
      console.log(`  ${user.padEnd(20)} (no results)`);
      continue;
    }
    if (r.status === 'crashed') {
      console.log(`  ${user.padEnd(20)} ⚠ CRASHED — ${r.message}`);
    } else {
      const icon = r.status === 'passed' ? '✓' : '✗';
      console.log(`  ${user.padEnd(20)} ${icon} ${r.passed} passed, ${r.failed} failed, ${r.skipped} skipped  (${r.durationSec}s)`);
    }
  }

  console.log('───────────────────────────────────────────────────────');
  console.log(`Total: ${totalPassed} passed, ${totalFailed} failed, ${totalSkipped} skipped`);
  console.log('═══════════════════════════════════════════════════════');

  if (totalFailed > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(`Aggregation failed: ${err.stack || err.message}`);
  process.exit(1);
});