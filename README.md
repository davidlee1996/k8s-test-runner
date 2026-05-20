# k8s-test-runner

> A distributed test execution platform that runs Playwright tests as Kubernetes Jobs.
> Built as a Senior SDET portfolio project — designed to demonstrate test infrastructure
> architecture, not just test authorship.

**Status:** Phase 1, Week 2 complete. Local Kind execution working end-to-end.
Parallelism, S3 results aggregation, and AWS EKS deployment coming in later phases.

---

## What this currently does

A single command spins up a local Kubernetes cluster, builds a containerized
Playwright test runner, deploys it as a Kubernetes Job, and reports test results:

```bash
make demo
```

The runner executes Playwright tests against [saucedemo.com](https://www.saucedemo.com),
a public demo site purpose-built for test automation. Test artifacts (JSON results,
screenshots, videos, traces) are written to a dedicated output directory inside the
container, isolated from the application code.

This isn't a flashy product — it's a reusable test infrastructure pattern that
mirrors how production test platforms are built.

---

## Quick demo

Prerequisites:
- Docker Desktop (running)
- Kind (`brew install kind`)
- kubectl (`brew install kubectl`)
- Make (preinstalled on macOS)

From a fresh checkout:

```bash
git clone https://github.com/davidlee1996/k8s-test-runner.git
cd k8s-test-runner
make demo
```

You'll see:
1. Kind cluster created (~30 seconds first time)
2. Docker image built for `linux/arm64` (~2–5 minutes first time, faster on rebuild)
3. Image loaded into Kind's container store
4. Kubernetes Job applied; pod logs stream to your terminal
5. Final status: `✅ Job succeeded` or `❌ Job failed`

To tear down when finished:

```bash
make cluster-down
```

---

## Architecture (current state)

```
Developer machine
       │
       ▼
   make demo
       │
       ├─▶ Kind cluster (local Kubernetes)
       │         │
       │         └─▶ Kubernetes Job
       │                    │
       │                    └─▶ Playwright Runner Pod
       │                              │
       │                              └─▶ Tests against saucedemo.com
       │                                       │
       │                                       └─▶ Results in /test-output/playwright
       │
       └─▶ kubectl logs streaming back to terminal
```

**What's not in this diagram yet:**
- Parallelism: currently a single pod runs all tests. Coming in Week 3.
- Results aggregation to AWS S3. Coming in Week 3.
- Terraform-managed AWS EKS deployment. Coming in Week 5.
- GitHub Actions CI. Coming in Phase 3.

---

## Design decisions worth highlighting

These are intentional choices, each made for a specific reason:

### Kubernetes Jobs (not Pods or Deployments)

Jobs are purpose-built for run-once batch workloads — they track completion,
handle retries via `backoffLimit`, and auto-clean via `ttlSecondsAfterFinished`.
A Deployment would be wrong (it's for always-running services); a bare Pod would
be wrong (no completion tracking at the controller level).

### `backoffLimit: 0` (fail fast)

Most tutorials default to higher backoff limits. For a test infrastructure platform,
retries paper over flakiness rather than surfacing it. The Job's success/failure
status should reflect the test's first-attempt result; retries are a separate
concern handled inside Playwright (currently `retries: 1`).

### Non-root container user

The Dockerfile drops to `pwuser` (provided by the Playwright base image) before
running tests. This matches what production Pod Security Standards require and
demonstrates the right pattern from day one.

### Code in `/app`, results in `/test-output/playwright`

Application code lives in a read-only directory owned by root. Mutable state
(test results, screenshots, traces) lives in a dedicated writable directory
owned by `pwuser`. This separation is the production pattern for containerized
test runners — code stays immutable, mutable state can be mounted as an
ephemeral volume in Kubernetes (coming in Week 3).

### Resource requests and limits set explicitly

Even for a single-pod Job, declaring `resources.requests` and `resources.limits`
in the Job manifest is good Kubernetes hygiene — it documents expected resource
usage and ensures the scheduler reserves capacity correctly when parallelism
is added later.

### Playwright workers = 1 inside each container

Parallelism is Kubernetes' job, not Playwright's. One pod = one Playwright worker
keeps resource usage predictable and makes K8s scheduling decisions meaningful.
When parallelism is added in Week 3, it'll be via K8s Job `parallelism` and
`completions` fields, not Playwright's internal worker pool.

### `data-test` attribute selectors via `getByTestId()`

Saucedemo exposes `data-test="..."` attributes on every interactive element
(a deliberate convention for test automation demos). Configuring Playwright's
`testIdAttribute: 'data-test'` lets us write clean `getByTestId('username')`
calls while still using the stable, contract-style attributes the site exposes.

---

## Repository structure

```
k8s-test-runner/
├── README.md                          ← you are here
├── Makefile                           ← orchestration
├── .gitignore
│
├── runner/                            ← Playwright test runner
│   ├── package.json
│   ├── playwright.config.js           ← env-driven output path, data-test selectors
│   ├── Dockerfile                     ← non-root pwuser, separate output dir
│   ├── .dockerignore
│   ├── .gitignore
│   └── tests/
│       ├── login.spec.js              ← 2 tests against saucedemo.com
│       └── fixtures/
│           └── users.js               ← test credentials (Sauce demo public docs)
│
├── k8s/                               ← Kubernetes manifests
│   └── runner-job.yaml                ← single Job, fail-fast, 5-min TTL
│
└── scripts/                           ← shell helpers
    ├── kind-up.sh                     ← idempotent cluster creation
    ├── kind-down.sh                   ← clean teardown
    ├── build-and-load.sh              ← docker buildx + kind load
    └── run-job.sh                     ← apply Job, stream logs, report status
```

---

## Roadmap

- [x] **Week 1** — Kubernetes ramp-up (Kind, kubectl, Jobs concept)
- [x] **Week 2** — Containerized Playwright runner on local Kind
- [ ] **Week 3** — Parallel execution + AWS S3 results aggregation
- [ ] **Week 4** — Terraform ramp-up (foundation for EKS)
- [ ] **Week 5** — Terraform-managed AWS EKS deployment with IRSA
- [ ] **Week 6–7** — GitHub Actions CI, architecture diagrams, polish

Each weekly milestone is tagged in git (`week-2-complete`, etc.) for easy rollback
and progress tracking.

---

## Technologies in use (Week 2)

| Layer | Tech |
|-------|------|
| Test framework | Playwright 1.49 (Chromium, headless) |
| Container | Docker (multi-arch buildx) |
| Local orchestration | Kind (Kubernetes-in-Docker) |
| Runtime | Kubernetes Jobs |
| Language | Node 20 |
| Build orchestration | Make |
| Target site | saucedemo.com (public Sauce Labs demo app) |

**Coming in later weeks:** AWS (EKS, S3, IAM, IRSA, ECR), Terraform, GitHub Actions.

---

## Available `make` targets

```bash
make demo         # Full pipeline: cluster up + build + load + run
make cluster-up   # Create Kind cluster (idempotent)
make cluster-down # Tear down Kind cluster
make build        # Build runner image and load into Kind
make run          # Apply Job and stream logs
make clean        # Delete the Job (cluster stays up)
make help         # Show this list
```

---

## Troubleshooting

If `make demo` fails, start with:

```bash
kubectl describe job playwright-runner
kubectl get events --sort-by='.lastTimestamp' | tail -20
kubectl logs -l job-name=playwright-runner
```

The most common Week 2 issues:
- **Docker disk full** — run `docker system prune -a --volumes`
- **Image not loading into Kind** — verify with `docker exec test-runner-dev-control-plane crictl images | grep k8s-test-runner`
- **Permission errors inside the container** — confirm `/test-output/playwright` is owned by `pwuser` in the image

---

## About this project

Built by [David Lee](https://www.linkedin.com/in/jaehyun-david-lee) as part of a
deliberate exploration of test infrastructure engineering — extending senior-SDET
experience at Amazon Robotics, Doble Engineering, and Walmart Advanced Systems
& Robotics into Kubernetes-native distributed execution patterns.

License: MIT (see `LICENSE`)