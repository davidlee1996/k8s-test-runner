# k8s-test-runner

> A distributed test execution platform that runs Playwright tests as Kubernetes Jobs.
> Built as a Senior SDET portfolio project — designed to demonstrate test infrastructure
> architecture, not just test authorship.

**Status:** Phase 1, Week 3 complete. Parallel execution + AWS S3 results aggregation working in GitHub Codespaces.
Terraform-managed AWS EKS deployment coming in Phase 2.

---

## What this currently does

A single command spins up a local Kubernetes cluster, builds a containerized Playwright runner,
deploys it as **four parallel Jobs** (one per Sauce demo user), uploads each pod's results to AWS S3,
and aggregates them into a unified per-user report:

```bash
make demo
```

The runner executes Playwright tests against [saucedemo.com](https://www.saucedemo.com),
a public site purpose-built for test automation. Each pod tests a different user with different
expected behaviors — standard, locked-out, performance-glitched, and intentionally-broken.

---

## Architecture (current state)

```
              ┌──────────────────────┐
              │   make demo          │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   Kind cluster       │
              │   (local K8s)        │
              └──────────┬───────────┘
                         │ applies 4 Jobs
            ┌────────────┼────────────┐
            ▼            ▼            ▼  ...
    ┌─────────────┐ ┌──────────┐ ┌──────────┐
    │ Pod         │ │ Pod      │ │ Pod      │
    │ STANDARD    │ │ PROBLEM  │ │ LOCKED_  │  ...
    │             │ │          │ │ OUT      │
    └──────┬──────┘ └─────┬────┘ └─────┬────┘
           │              │            │
           │ Playwright tests run; results upload to S3
           └──────────────┴────────────┘
                          │
                          ▼
              ┌──────────────────────┐
              │   AWS S3 bucket      │
              │   runs/<RUN_ID>/...  │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   Aggregator         │
              │   per-user summary   │
              └──────────────────────┘
```

**What's not in this diagram yet** (Phase 2):
- AWS EKS deployment via Terraform (replaces local Kind)
- ECR for image distribution (replaces `kind load`)
- IRSA for AWS auth (replaces K8s Secrets with static credentials)

---

## Quick demo (Codespaces)

This project develops in GitHub Codespaces. The `.devcontainer/` config provisions a
Linux dev environment with all required tooling.

1. Open the repo in Codespaces (Code → Codespaces → Create codespace on main)
2. Wait for setup to complete (~2-3 minutes the first time)
3. In the terminal:
   ```bash
   make doctor   # verify all tools and credentials
   make demo     # full pipeline end-to-end
   ```

Expected output of `make demo`:
```
Per-user breakdown:
───────────────────────────────────────────────────────
  STANDARD              ✓ 4 passed, 0 failed, 0 skipped  (12.3s)
  LOCKED_OUT            ✓ 1 passed, 0 failed, 3 skipped  (5.1s)
  PROBLEM               ✓ 3 passed, 1 failed, 0 skipped  (13.4s)
  PERFORMANCE_GLITCH    ✓ 4 passed, 0 failed, 0 skipped  (18.2s)
───────────────────────────────────────────────────────
Total: 12 passed, 1 failed, 3 skipped
```

See `docs/CODESPACES_SETUP.md` for one-time setup details (including how to add AWS credentials as Codespaces secrets).

---

## Design decisions worth highlighting

These are intentional choices, each made for a specific reason:

### Per-user parameterized testing (contract-driven)

Instead of running the same suite 4× with different credentials, each pod tests a different
**user persona** with documented expected behavior. The `users.js` fixture defines an `expectations`
contract per user (`canLogin`, `cartWorks`, `hasVisualGlitches`, etc.). The tests assert behavior
matching the expectations.

Adding a new persona is a single fixture entry. The test suite scales by contract, not by code.

### Kubernetes Jobs (one per user, not indexed parallelism)

K8s offers two ways to run N parallel pods of the same workload: a single Job with `parallelism: N`,
or N separate Jobs. We use the latter because each Job has a distinct purpose visible at a glance
from `kubectl get jobs` (`playwright-standard`, `playwright-problem`, etc.). For sharded workloads
where pods are interchangeable, indexed Jobs would be more idiomatic.

### Results upload happens regardless of test outcome

The container entrypoint runs Playwright, **captures** its exit code, runs the S3 upload regardless
of pass/fail, then exits with Playwright's original code. This ensures the aggregator sees failure
details when tests fail. A failed test should not also lose its failure metadata.

### Shared `RUN_ID` across parallel pods

A single `RUN_ID` (timestamp + random suffix) is generated once per `make demo` and injected as an
env var into all 4 Jobs. Every pod uploads to `s3://bucket/runs/<RUN_ID>/<user>/<pod>/results.json`.
The aggregator lists everything under `runs/<RUN_ID>/` to find that run's results — no separate
tracking system needed.

### Kubernetes Secrets for AWS credentials (Phase 1 only)

In Phase 1, AWS credentials are stored as a Kubernetes Secret and injected as env vars. This is
the standard pattern for static credentials but has limitations: long-lived, plaintext in etcd,
no auto-rotation. **Phase 2 replaces this with IRSA** (IAM Roles for Service Accounts), which
issues short-lived auto-rotated credentials per pod via EKS's OIDC provider. The deliberate
migration to IRSA is itself a portfolio talking point.

### Non-root container user, separated output directory

The Dockerfile drops to `pwuser` (provided by the Playwright base image) before running tests.
Application code lives in `/app` (read-only, root-owned); mutable state lives in
`/test-output/playwright` (writable, pwuser-owned). This matches production Pod Security Standards
and makes the container compatible with K8s volume mounts.

### Fail fast on test failures (`backoffLimit: 0`)

Most tutorials default to higher backoff limits. For a test infrastructure platform, retries paper
over flakiness rather than surfacing it. The Job's success/failure status reflects the test's
first-attempt result; Playwright handles its own retry budget separately (currently `retries: 1`).

### Playwright `workers: 1` inside each container

Parallelism is Kubernetes' job, not Playwright's. One pod = one Playwright worker keeps resource
usage predictable. K8s scheduling decisions are meaningful when each pod consumes well-defined
CPU/memory.

### `data-test` attribute selectors

Saucedemo exposes `data-test="..."` attributes on every interactive element (a deliberate
convention for test automation). Configuring `testIdAttribute: 'data-test'` in Playwright lets
us write clean `getByTestId('username')` calls while still using the stable, contract-style
attributes the site exposes. Selectors are robust to UI refactors.

---

## Repository structure

```
k8s-test-runner/
├── README.md                          ← you are here
├── Makefile                           ← orchestration
├── .gitignore
├── .devcontainer/                     ← Codespaces config
│   ├── devcontainer.json
│   └── setup.sh
│
├── runner/                            ← Playwright test runner
│   ├── package.json                   ← Playwright + @aws-sdk/client-s3
│   ├── playwright.config.js
│   ├── Dockerfile                     ← non-root pwuser, separate output dir
│   ├── entrypoint.sh                  ← runs tests + uploads to S3 regardless of outcome
│   ├── upload-results.js              ← S3 uploader for one pod's results
│   ├── aggregate-results.js           ← cross-pod results aggregator
│   └── tests/
│       ├── login.spec.js              ← parameterized by SAUCE_USER env var
│       ├── inventory.spec.js          ← cart & inventory tests per user
│       └── fixtures/
│           └── users.js               ← per-user expectations contracts
│
├── k8s/
│   └── runner-job.template.yaml       ← envsubst-templated Job (one per user)
│
├── scripts/                           ← orchestration helpers (no Node dependencies)
│   ├── kind-up.sh
│   ├── kind-down.sh
│   ├── build-and-load.sh
│   ├── create-secret.sh               ← creates K8s Secret from local AWS creds
│   ├── run-jobs.sh                    ← renders 4 Jobs, applies in parallel, waits for completion
│   └── doctor.sh                      ← health check
│
└── docs/
    ├── AWS_SETUP.md                   ← one-time AWS setup (S3 bucket, IAM user, policy)
    ├── CODESPACES_SETUP.md            ← Codespaces + VS Code Desktop walkthrough
    └── WEEK3.md                       ← Week 3 implementation details
```

---

## Roadmap

- [x] **Week 1** — Kubernetes ramp-up (Kind, kubectl, Jobs concept)
- [x] **Week 2** — Containerized Playwright runner on local Kind
- [x] **Week 3** — Parallel execution + AWS S3 results aggregation
- [ ] **Week 4** — Terraform ramp-up (foundation for EKS)
- [ ] **Week 5** — Terraform-managed AWS EKS deployment with IRSA + ECR
- [ ] **Week 6–7** — GitHub Actions CI, architecture diagrams, polish

Each weekly milestone is tagged in git (`week-2-complete`, `week-3-complete`, etc.) for clean
rollback and progress tracking.

---

## Technologies in use (Week 3)

| Layer | Tech |
|-------|------|
| Test framework | Playwright 1.49 (Chromium, headless) |
| Test parameterization | Env-var-driven user selection via fixtures |
| Container | Docker (Linux x86_64 in Codespaces) |
| Local orchestration | Kind (Kubernetes-in-Docker) |
| Workload model | K8s Jobs (4 parallel, one per user) |
| Language | Node 20 |
| Results storage | AWS S3 (single bucket, prefix-based per run) |
| AWS auth | K8s Secret with static credentials (will become IRSA in Phase 2) |
| Build orchestration | Make |
| Target site | saucedemo.com |
| Dev environment | GitHub Codespaces (Ubuntu 24.04) |

**Coming in Phase 2:** AWS (EKS, ECR, IAM, IRSA), Terraform.

---

## Available `make` targets

```bash
# Setup
make doctor       # Verify tools, credentials, and cluster state

# Pipeline (in order)
make cluster-up   # Create Kind cluster
make build        # Build image and load into Kind
make secret       # Create K8s Secret with AWS credentials
make run          # Render and apply 4 Jobs (one per Sauce demo user)
make aggregate    # Pull results from S3 and print unified summary

# Composed
make demo         # Full pipeline: cluster + build + secret + run + aggregate

# Teardown
make clean        # Delete all Jobs (cluster stays up)
make cluster-down # Tear down Kind cluster entirely
```

---

## About this project

Built by [David Lee](https://www.linkedin.com/in/jaehyun-david-lee) as a deliberate exploration
of test infrastructure engineering — extending senior SDET experience at Amazon Robotics, Doble
Engineering, and Walmart Advanced Systems & Robotics into Kubernetes-native distributed execution
patterns.

License: MIT (see `LICENSE`)