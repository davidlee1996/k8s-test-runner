# Week 3 — Parallel Execution + S3 Results Aggregation

> Phase 1, Week 3: extends the Week 2 single-pod runner into a distributed execution platform
> with per-user parameterization, AWS S3 results storage, and unified aggregation.

This doc covers what Week 3 added, why each piece works the way it does, and how the moving
parts fit together. For one-off setup (S3 bucket, IAM user), see `AWS_SETUP.md`. For environment
setup (Codespaces), see `CODESPACES_SETUP.md`.

---

## The goal in one sentence

Run the same Playwright test suite as four different Sauce demo users in parallel pods, with
each pod uploading its results to S3 so a separate aggregator can produce a unified report.

## What changed from Week 2

| Concept | Week 2 | Week 3 |
|---|---|---|
| Workload | Single Job, single pod | Four parallel Jobs, one per user |
| Test parameterization | Hardcoded credentials | Reads `SAUCE_USER` env var; behavior expectations per user |
| Test suite | 2 tests (login happy path + locked-out) | 5 tests across login + inventory specs |
| Results | Streamed via `kubectl logs` | Uploaded to S3 per pod |
| Aggregation | None (read logs manually) | Aggregator script downloads S3 results, prints per-user summary |
| AWS auth | None | Static credentials via K8s Secret |
| Pod identity | Not used | Pulled via downward API for unique S3 keys |
| Container entrypoint | `npx playwright test` | Custom script: run tests → upload results → exit with test code |

---

## The execution flow

```
make demo
   │
   ├─▶ cluster-up        → Kind cluster running
   │
   ├─▶ build             → Docker image built, loaded into Kind
   │
   ├─▶ secret            → AWS credentials stored as K8s Secret
   │
   ├─▶ run               → 4 Jobs applied with shared RUN_ID
   │       │
   │       ├─▶ Pod STANDARD            ┐
   │       ├─▶ Pod LOCKED_OUT          │  All parallel, all uploading to S3
   │       ├─▶ Pod PROBLEM             │  under runs/<RUN_ID>/<user>/<pod>/...
   │       └─▶ Pod PERFORMANCE_GLITCH  ┘
   │
   └─▶ aggregate         → Pull results from S3, print per-user summary
```

Each phase is its own make target and can be run independently for debugging.

---

## Per-pod lifecycle

When `kubectl` schedules a pod, its container runs `entrypoint.sh`, which:

```
1. Print pod context (which user, run ID, bucket)
2. npx playwright test           ← Playwright runs, writes results.json
3. Capture Playwright's exit code (don't fail the script yet)
4. node upload-results.js        ← Always runs, regardless of test outcome
5. Decide exit code:
   - If tests failed → exit with Playwright's code (Job correctly fails)
   - If tests passed but upload failed → exit non-zero (still notice it)
   - Otherwise → exit 0
```

**Why the upload runs unconditionally:** A failing test that doesn't upload its failure details
is useless. The aggregator needs the full results.json — pass or fail — to produce a meaningful
per-user breakdown. The Job's success/failure status reflects the **tests**, not the upload step.

---

## The S3 key structure

Each pod uploads to:

```
runs/<RUN_ID>/<SAUCE_USER>/<POD_NAME>/results.json
```

A concrete example:

```
s3://k8s-test-runner-results-bucket/runs/20260520-143022-x7k2n9/STANDARD/playwright-standard-abc12/results.json
s3://k8s-test-runner-results-bucket/runs/20260520-143022-x7k2n9/LOCKED_OUT/playwright-locked-out-def34/results.json
s3://k8s-test-runner-results-bucket/runs/20260520-143022-x7k2n9/PROBLEM/playwright-problem-ghi56/results.json
s3://k8s-test-runner-results-bucket/runs/20260520-143022-x7k2n9/PERFORMANCE_GLITCH/playwright-performance-glitch-jkl78/results.json
```

Why this structure:

- **`runs/<RUN_ID>/...` prefix** lets the aggregator list everything from one run with a single
  S3 ListObjectsV2 call. No separate index, no metadata table.
- **`<SAUCE_USER>/` segment** makes the user identity readable in S3 console / `aws s3 ls` output.
- **`<POD_NAME>/` segment** is unique per pod, eliminating any collision risk if Jobs ever
  retry or scale.

`POD_NAME` comes from the **Kubernetes downward API** — a feature that lets a pod read its own
metadata at runtime. The Job spec includes:

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

This is the standard pattern for K8s-aware applications. The pod doesn't need to generate UUIDs
or coordinate identity — K8s assigns each pod a unique auto-suffixed name (e.g.,
`playwright-standard-abc12`), and the downward API exposes it.

---

## Why one Job per user (not one Job with parallelism: 4)

Kubernetes has two patterns for running N parallel pods of the same workload:

**Indexed Job:** one Job with `parallelism: 4`, `completions: 4`, `completionMode: Indexed`.
Each pod gets a `JOB_COMPLETION_INDEX` env var (0..3) and selects what to do based on that.

**Multiple Jobs:** four separate Jobs, each parameterized differently before applying.

Week 3 uses the **multiple Jobs** pattern. Tradeoffs:

| Aspect | Multiple Jobs (current) | Indexed Job |
|---|---|---|
| `kubectl get jobs` readability | High — each Job's purpose is visible from its name | Lower — pods differ only by index |
| Independent failure reporting | Each Job's success/failure is independently tracked | All-or-nothing at the Job level |
| Code simplicity | Slightly more orchestration (template + envsubst loop) | Cleaner manifest, more env-var logic in code |
| Resource semantics | 4 distinct workloads | 1 workload run 4 times |

For four user personas with **distinct contracts**, multiple Jobs match the mental model better.
For a fleet of interchangeable test shards, indexed Jobs are more idiomatic.

This decision is worth being able to explain in interviews. "Why not indexed Jobs?" is a real
SRE-style question and "each Job represents a distinct user contract, so visibility at the Job
level matched our model better" is a real answer.

---

## Per-user contract testing

The `users.js` fixture defines each user with an `expectations` object:

```javascript
STANDARD: {
  expectations: {
    canLogin: true,
    inventoryRenders: true,
    cartWorks: true,
    checkoutWorks: true,
    hasVisualGlitches: false,
    isSlow: false,
  },
},
LOCKED_OUT: {
  expectations: {
    canLogin: false,
    lockoutErrorVisible: true,
  },
},
// ... etc
```

The tests use these expectations to choose assertions:

- `login.spec.js`: if `canLogin: true`, expect inventory page; otherwise expect the locked-out error
- `inventory.spec.js`: `test.skip` entirely if `canLogin: false`, since you can't reach inventory without logging in
- The cart-add test has different assertions for `cartWorks: true` vs `false` (the `PROBLEM` user has documented cart bugs)

This is **contract-driven testing**. Adding a new user persona is a single fixture entry — the
test suite scales by contract, not by code. Each user's S3-uploaded results document its
expected behavior in machine-readable form.

---

## The Kubernetes Secret pattern

AWS credentials live in a Kubernetes Secret named `aws-credentials`. The Job spec references it
via `secretKeyRef`:

```yaml
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: aws-credentials
      key: AWS_ACCESS_KEY_ID
```

K8s injects the value as an env var when the pod starts. The credentials are never written to
the image, never committed to git, never visible in `kubectl get pods -o yaml`.

**Limitations of this pattern (worth knowing for interviews):**
- Long-lived credentials, no rotation
- Plaintext in etcd by default (encryption-at-rest is configurable but not on by default in Kind)
- Anyone with cluster admin can `kubectl get secret aws-credentials -o yaml` and decode it

**Why we use it in Phase 1 anyway:** Kind doesn't have an OIDC provider, so IRSA isn't an option
locally. Static credentials + K8s Secret is the standard fallback for local development.

**Phase 2 (Week 5) replaces this with IRSA** — IAM Roles for Service Accounts. The Pod's
ServiceAccount is annotated with an IAM role ARN; AWS SDK auto-discovers credentials via the
EKS OIDC provider; credentials are short-lived and auto-rotate. No long-lived secrets in the
cluster.

The explicit migration path (Secret → IRSA) is itself a portfolio talking point.

---

## The aggregator

`runner/aggregate-results.js` is a standalone Node script that:

1. Reads `RUN_ID` from `/tmp/k8s-test-runner-last-run-id` (set by `run-jobs.sh`) or from CLI arg
2. Lists `s3://<bucket>/runs/<RUN_ID>/` to find all uploaded result files
3. Downloads each file
4. Parses Playwright's `results.json` for stats: passed, failed, skipped, duration
5. Prints a per-user summary table

Why this lives in `runner/` and not `scripts/`: it depends on `@aws-sdk/client-s3`, which is in
`runner/package.json` → `runner/node_modules`. Node resolves modules by walking up from the
**script's location**, not from the invocation directory. Files that depend on `node_modules`
need to live in or under the directory that owns it.

The aggregator can be invoked:
- From a specific RUN_ID: `node aggregate-results.js 20260520-143022-x7k2n9`
- From the last run: `node aggregate-results.js` (reads `/tmp/k8s-test-runner-last-run-id`)
- Via the Makefile: `make aggregate` (loads credentials + invokes from `runner/`)

---

## What "Week 3 complete" verification looks like

The full pipeline:

```bash
make doctor      # All checks green
make demo        # End-to-end pipeline
```

Expected aggregator output:

```
═══════════════════════════════════════════════════════
  Aggregating results for run: 20260520-143022-x7k2n9
  Bucket: k8s-test-runner-results-...
  Prefix: runs/20260520-143022-x7k2n9/
═══════════════════════════════════════════════════════

Found 4 result files:

Per-user breakdown:
───────────────────────────────────────────────────────
  STANDARD              ✓ 4 passed, 0 failed, 0 skipped  (12.3s)
  LOCKED_OUT            ✓ 1 passed, 0 failed, 3 skipped  (5.1s)
  PROBLEM               ✓ 3 passed, 1 failed, 0 skipped  (13.4s)
  PERFORMANCE_GLITCH    ✓ 4 passed, 0 failed, 0 skipped  (18.2s)
───────────────────────────────────────────────────────
Total: 12 passed, 1 failed, 3 skipped
═══════════════════════════════════════════════════════
```

Notes on these numbers:
- **`LOCKED_OUT` shows 3 skipped** because `inventory.spec.js` calls `test.skip()` when the user
  can't log in. That's expected behavior, not a missing test.
- **`PROBLEM` may show 1 failed** because saucedemo's `problem_user` has intentional bugs; the
  cart-add test logs the bug rather than strictly asserting. The exact pass/fail count for this
  user reflects whichever bug is currently broken at saucedemo.
- **`PERFORMANCE_GLITCH` takes ~18s** because saucedemo intentionally injects delays for that
  user. Test timeouts are tuned to accommodate this.

You can also verify in S3 directly:

```bash
source ~/.k8s-test-runner-credentials
aws s3 ls s3://${S3_BUCKET}/runs/ --recursive
```

You should see 4 result files for each `RUN_ID`.

---

## Interview talking points unlocked by Week 3

Things you can substantively discuss in interviews now that this is built:

**"How do you ensure failed test results still make it to the aggregator?"**
→ The entrypoint runs the upload regardless of Playwright's exit code. The pod's final exit
status reflects the tests, but upload runs unconditionally. Without this, failing tests would
have no aggregated visibility — the opposite of what test infrastructure should do.

**"How do you give pods AWS credentials in Kubernetes?"**
→ In Phase 1, Kubernetes Secrets injected as env vars via `secretKeyRef`. Honest about the
limitations (static, long-lived, plaintext-at-rest). In Phase 2, IRSA — IAM Roles for Service
Accounts — which uses short-lived auto-rotated credentials issued by EKS's OIDC provider. The
explicit migration is part of the project narrative.

**"How does the aggregator know which pods belong to one run?"**
→ A shared `RUN_ID` (timestamp + random suffix) is generated once by `run-jobs.sh` and injected
as an env var into all 4 Jobs. Every pod uploads to `runs/<RUN_ID>/...` in S3. The aggregator
lists everything under `runs/<RUN_ID>/` with a single S3 ListObjectsV2 — no separate index or
tracking system.

**"How do you handle pod identity for unique S3 keys?"**
→ Kubernetes downward API. The Job spec includes a `fieldRef` that injects `metadata.name` as
the `POD_NAME` env var. The pod doesn't need to generate UUIDs or coordinate identity — K8s
already assigns each pod a unique name, and the downward API exposes it.

**"Why one Job per user instead of indexed parallelism?"**
→ Each Job represents a distinct user persona with its own contract. Having each Job named for
its purpose (`playwright-standard`, `playwright-problem`, etc.) makes `kubectl get jobs` readable
and independent failure tracking trivial. For interchangeable shards where pods differ only by
index, indexed Jobs would be more idiomatic.

---

## What's NOT in Week 3

For completeness:

- **IRSA** — replaces static AWS credentials in pods. Coming in Week 5.
- **ECR** — replaces `kind load` for image distribution to EKS. Coming in Week 5.
- **Terraform-managed cluster** — replaces Kind for production-grade deployment. Coming in
  Weeks 4-5.
- **CI on every PR** — GitHub Actions runs the Kind-based demo on every PR. Coming in Week 6-7.
- **Polished README** — the recruiter-facing version with diagrams and design pitch. Phase 3
  deliverable.

---

## Tagging Week 3 complete

```bash
git add .
git commit -m "Phase 1 Week 3: parallel execution + S3 results aggregation"
git tag week-3-complete
git push --tags
```

Move on to Week 4 (Terraform ramp-up) when ready.